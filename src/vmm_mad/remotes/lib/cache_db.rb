#!/usr/bin/env ruby
# -------------------------------------------------------------------------- #
# Copyright 2002-2019, OpenNebula Project, OpenNebula Systems                #
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
# -------------------------------------------------------------------------- #
require 'sqlite3'

# Store instances info to simple local db
class InstanceCache

    def initialize(path)
        @db = SQLite3::Database.new(path)

        bootstrap
    end

    def execute_retry(query, tries=5, tsleep=0.5)
        i=0
        while i < tries
            begin
                return @db.execute(query)
            rescue SQLite3::BusyException
                i += 1
                tsleep 0.5
            end
        end
    end

    def bootstrap
        sql = 'CREATE TABLE IF NOT EXISTS vms(uuid VARCHAR(128) PRIMARY KEY,'
        sql << ' id INTEGER, name VARCHAR(128), state VARCHAR(128),'
        sql << ' type VARCHAR(128))'
        execute_retry(sql)

        sql = 'CREATE TABLE IF NOT EXISTS timestamp(ts INTEGER PRIMARY KEY)'
        execute_retry(sql)
    end

    def insert(instances)
        execute_retry('DELETE from vms')
        instances.each do |i|
            sql = 'INSERT INTO vms VALUES ('
            sql << "\"#{i[:uuid]}\", "
            sql << "\"#{i[:id]}\", "
            sql << "\"#{i[:name]}\", "
            sql << "\"#{i[:state]}\", "
            sql << "\"#{i[:type]}\")"

            execute_retry(sql)
        end

        execute_retry('DELETE from timestamp')
        instances.each do |_i|
            execute_retry("INSERT INTO timestamp VALUES (#{Time.now.to_i})")
        end
    end

    def select_vms()
        vms = []
        execute_retry('SELECT * from vms').each do |vm|
            vms << Hash[[:uuid, :id, :name, :state, :type].zip(vm)]
        end

        vms
    end

    def select_timestamp
        ts = execute_retry('SELECT * from timestamp')
        return 0 if ts.empty?

        ts.first.first
    end

end
