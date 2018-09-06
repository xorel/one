#!/usr/bin/env ruby

# -------------------------------------------------------------------------- #
# Copyright 2002-2018, OpenNebula Project, OpenNebula Systems                #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

require 'socket'
require 'base64'
require 'resolv'
require 'ipaddr'
require 'zlib'


DIRNAME = File.dirname(__FILE__)
REMOTE_DIR_UPDATE = File.join(DIRNAME, '../../.update')

class CollectdClient
    def initialize(hypervisor, number, host, port, probes_args,
                   monitor_push_period)
        # Arguments
        @hypervisor          = hypervisor
        @number              = number.to_i
        @host                = get_ipv4_address(host)
        @port                = port
        @monitor_push_period = monitor_push_period

	@default_vm_monitor_interval = "300"
        # Probes
        run_probes_cmd = File.join(DIRNAME, '..', "run_probes")
        @run_probes_cmd = "#{run_probes_cmd} #{@hypervisor}-probes #{probes_args}"

        # Get last update
        @last_update = get_last_update

        # Socket
        @s = UDPSocket.new
	@time_stamp = Hash.new
	@previous_state = Hash.new
#	@counter = 0
#	@samples = 3
#	@variable_elements = ["FREECPU", "FREEMEMORY", "USEDCPU", "USEDMEMORY"]
#	@data_array = Array.new
#	@last_data = String.new
    end

    def get_ipv4_address(host)
        addresses=Resolv.getaddresses(host)
        address=nil

        addresses.each do |addr|
            begin
                a=IPAddr.new(addr)
                if a.ipv4?
                    address=addr
                    break
                end
            rescue
            end
        end

        address
    end

    def run_probes
        data   = `#{@run_probes_cmd} 2>&1`
        code   = $?.exitstatus == 0

        [data, code]
    end

#    def check_data(data)	
#	alert = false	
#	File.open("/tmp/data", 'a') {|f| f.write("checking data data = #{data}") }
#	free_mem = data[0].split('FREEMEMORY=')[1].split("\n")[0].to_f
#	total_mem = data[0].split('TOTALMEMORY=')[1].split("\n")[0].to_f
#	File.open("/tmp/data", 'a') {|f| f.write("end data") }
#	if free_mem/total_mem < 0.15
#		alert = true
#	end
#
#	if @array_data.length > 1
#		last_data = @array_data.last
#	elsif !@last_data.empty
#		last_data = @last_data
#	end
#	
#	if !last_data.empty?
#	if !last_data.empty?
#		puts "check host and vm status condition"
#	end
#
#	File.open("/tmp/data", 'a') {|f| f.write("alert status = #{alert}") }
#	puts alert
#   end

    def process_data(data)
	parsed_data = parse_data(data)    
	return_elements = Array.new
	parsed_data[1].each { |vm|
	    id = vm[0].scan(/ID=(\d+),/)[0][0].to_i
	    current_state = vm[0].scan(/STATE=(.)/)[0][0]
	    @previous_state[id] = current_state
	    if @time_stamp.key?(id) and @previous_state.key?(id)
		vm_monitoring_interval = vm[0].scan(/MONITOR_POLL=(\d+),/)[0] || [@default_vm_monitor_interval]
		vm_monitoring_interval = vm_monitoring_interval[0].to_i
		if Time.now - @time_stamp[id] > vm_monitoring_interval || @previous_state[id] != current_state
   	            @time_stamp[id] = Time.now
		    return_elements.push(vm)
		end
	    else
	        @time_stamp[id] = Time.now
		return_elements.push(vm)
	    end
	} 
	data = merge_data(parsed_data[0], return_elements) 
	
	data
    end

    def merge_data(header, vm_array)
	data = header
	vm_array.each { |vm|
	    data << "\nVM=#{vm[0]}]"
	}
	data
    end

    def parse_data(data)
	data_array = Array.new
	info_header = String.new
	info_header = data.split("VM_POLL")[0]
	info_header << "VM_POLL=YES"
	vm_data = data.split("VM_POLL")[1]
	data_array = vm_data.scan(/^VM=(.+?)\]/m)
        [info_header, data_array]
    end

#    def get_averages	
#	values = Array.new
#		averaged_data = @data_array.last
#	File.open("/tmp/data", 'a') {|f| f.write("data array  = #{@data_array}") }
#	@variable_elements.each do |parameter|
#	    @data_array.each do |data|
#		values.push(data.split("#{parameter}=")[1].split("\n")[0].to_f)
#	File.open("/tmp/data", 'a') {|f| f.write("values  = #{values}") }
#	    end
#	    average = values.reduce(:+)/values.size
#	File.open("/tmp/data", 'a') {|f| f.write("average  = #{average}") }
#	    replace_string = "#{parameter}=#{averaged_data.split("#{parameter}=")[1].split("\n")[0]}"
#	File.open("/tmp/data", 'a') {|f| f.write("replace string  = #{replace_string}") }
#	    averaged_data = averaged_data.gsub(replace_string, "#{parameter}=#{average}")
#	end
	#File.open("/tmp/data", 'a') {|f| f.write("averaged_data = #{averaged_data}") }
#	averaged_data
#    end


    def send(data)
        message, code = data
        result = code ? "SUCCESS" : "FAILURE"
        
	zdata  = Zlib::Deflate.deflate(message, Zlib::BEST_COMPRESSION)
        data64 = Base64::encode64(zdata).strip.delete("\n")
        
	@s.send("MONITOR #{result} #{@number} #{data64}\n", 0, @host, @port)
	#@last_data = @data_array.pop
	#@data_array.clear
	#@counter = 0
    end

    def monitor
        loop do
            # Stop the execution if we receive the update signal
            exit 0 if stop?

            # Collect the Data
            ts = Time.now
            data = run_probes

            run_probes_time = (Time.now - ts).to_i
	    #@data_array.push(data[0])


	    # Send the Data
	    if data[1] and data[0].match(/VM_POLL=YES/)
		data[0] = process_data(data[0])
	    end
	    #elsif @counter == @samples or check_data(data)
	    #	data[0] = get_averages

	    send data
            # Sleep during the Cycle
            sleep_time = @monitor_push_period - run_probes_time
            sleep_time = 0 if sleep_time < 0
            sleep sleep_time
        end
    end

    def get_last_update
        File.stat(REMOTE_DIR_UPDATE).mtime.to_i rescue 0
    end

    def stop?
        get_last_update.to_i != @last_update.to_i
    end
end

#Arguments: hypervisor(0) ds_location(1) collectd_port(2) monitor_push_period(3)
#                         host_id(4) hostname(5)

hypervisor          = ARGV[0]
port                = ARGV[2]
monitor_push_period = ARGV[3].to_i
number              = ARGV[4]

#monitor_push_period = 20 if monitor_push_period == 0
monitor_push_period = 5 if monitor_push_period == 0

host       = ENV['SSH_CLIENT'].split.first
probes_args= ARGV[1..-1].join(" ")

# Add a random sleep before the first send
#sleep rand monitor_push_period

# Start push monitorization
client = CollectdClient.new(hypervisor, number, host, port, probes_args,
                            monitor_push_period)
client.monitor
