#!/bin/env ruby

class CiscoConfigParse
    def initialize(raw_text_config, debug=false)
        @raw_text_config = raw_text_config
        @config_lines = raw_text_config.gsub(/banner motd \^C\n.*^\^/m, '').split(/\n/).reject(&:empty?)
        @deb = debug
    end

    def parse
        @banner = @raw_text_config[/(?<=banner motd \^C\n).*(?=^\^)/m]
        
        @config_lines.each do |line|
            if line =~ /^\!$/ or line =~ /^$/ # terminate current block
                print "└───\n\n" if @deb
                print "┌───\n" if @deb
                end_config
                next
            elsif line =~ /^\b/
                print "└───\n\n" if @deb
                print "┌───\n" if @deb
                end_config
            elsif line =~ /^\!/ or line =~ /^\ $/ # Comment
                print "-" if @deb
                next
            end
            print "├" + line.gsub(/[^\w]\ /, "─") + "\n" if @deb
            parse_config(line)
        end
    end

    def get_interfaces
        return @interfaces
    end

    def get_vlans
        return @vlans
    end

    def get_banner
        return @vlans
    end

    def get_hostname
        return @config_hostname
    end

    def get_version
        return @software_version
    end

    private
    def state
        @state ||= []
    end
    def end_config
        meth = ['e_config', state].flatten.join('_')
        # p meth.to_s + "--" + state.to_s if respond_to?(meth, :include_private)
        send(meth) if respond_to?(meth, :include_private)
        state.pop
    end
    def parse_config(line)
        cmd, opts = line.strip.split(' ', 2)
        # p line
        case state.last
        when :ip_access_list_IOS_STANDARD, :ip_access_list_IOS_EXTENDED, :ip_access_list_NXOS
            meth, opts = ['p_config', state].flatten.join('_'), line.strip
        else
            meth, opts = meth_and_opts(cmd, opts)
        end
        # p meth.to_s + " -> " + opts.to_s + " -" + respond_to?(meth, :include_private).to_s
        send(meth, opts) if respond_to?(meth, :include_private)
    end
    def meth_and_opts(cmd, opts)
        return negated_meth_and_opts(opts) if cmd =~ /^no$/
            [['p_config', state, cmd.gsub('-', '_')].flatten.join('_'), opts]
    end
    def negated_meth_and_opts(line)
        cmd, opts = line.split(' ', 2)
        [['n_config', state, cmd.gsub('-', '_')].flatten.join('_'), opts]
    end

    protected

    def p_config_ipv4(i)
        p_config_ip(i)
    end
    def p_config_ip(str)
        command = str.split(' ', 3)
        # p command
        case command[0]
        when "domain-name"
            @domain_name = command[1]
        when "access-list"

            case command[1]
            when "standard"
                state.push(:ip_access_list_IOS_STANDARD)
            when "extended"
                state.push(:ip_access_list_IOS_EXTENDED)
            else
                state.push(:ip_access_list_NXOS)
                @current_acl = {:name => command[1]}        
            end
        else
        # exit            
        end
            
    end

    def p_config_ip_access_list_NXOS(acl)
        acl = acl.split(' ')
        seq = acl.shift.to_i
        action = acl.shift

        @current_acl[seq] = {
            seq: seq,
            action: action
        }
        dirr, dirc = "src", false
        acl.each_with_index { |word, i|
            # print "-#{word}-"
            case word
            when "eq", "gt", "net-group", "port-group"
                _1 = acl[i]
                _2 = acl[i+1]
                @current_acl[seq][_1.to_sym] = _2
            when "ahp","eigrp","esp","gre","icmp","igmp","igrp","ipinip","ipv4","nos","ospf","pcp","pim","sctp","tcp","udp",/^[0-255]$/
                @current_acl[seq][:protocol] = acl[i]
            when "any", /^(?:\d{1,3}\.){3}\d{1,3}(?:\/\d{1,2})?$/
                dirr = "dst" if dirc
                @current_acl[seq][:"#{dirr}"] = acl[i]
                dirc = true
            when "host"
                dirr = "dst" if dirc
                _1 = acl[i]
                _2 = acl[i+1]
                @current_acl[seq][:"#{dirr}"] = _2
                dirc = true
            else
                next
            end
        }
        p @current_acl[seq]
        # exit
    end

    def p_config_hostname(str)
        @config_hostname = str
    end

    def p_config_version(str)
        @software_version = str
    end

    def p_config_vlan(ids)
        case ids
        when "configuration"
            # Enters the vlan feature configuration mode
            # (Allows you to configure VLANs without actually creating them)
        when /^[0-9]+$/
            state.push(:vlan)
            @current_vlan = {:ids => ids}
        end
        # return if ids =~ /^[^0-9]+$/
        # print "ids=" + ids + "\n"
    end

    def p_config_vlan_mode(mode)
        @current_vlan[:mode] = mode
    end

    def e_config_vlan
        @vlans ||= {}
        @current_vlan[:mode] = "ce" if @current_vlan[:mode].nil?
        @vlans[@current_vlan.delete(:ids)] = @current_vlan
    end

    def p_config_interface(name)
        state.push(:interface)
        @current_interface = {:id => name}
    end

    def p_config_interface_description(str)
        @current_interface[:description] = str
    end

    def p_config_interface_switchport(str)
        # Parse the switchport string
        return if str.nil?

        command = str.split(' ', 3)
        case command[0]
        when "trunk"
            # Its a trunk command; continue to figure out what kind
            if command[1] == "allowed"
                # allow vlan
                allowed_type = str.split(' ', 5)
                # Split up the rest of the string for the list of vlans
                vlan_list = str.gsub(',',' ').split(' ')
                if allowed_type[3] == "add" then
                    @current_interface[:added_allowed_vlans] = vlan_list.slice(4, vlan_list.length)
                else
                    @current_interface[:allowed_vlans] = vlan_list.slice(3, vlan_list.length)
                end
            end
        when "access"
            @current_interface[:access_vlan] = command[2]
        when "mode"
            @current_interface[:mode] = command[1]
        end
    end

    def p_config_interface_inherit(str)
        @current_interface[:inherit] = str
    end

    def p_config_interface_spanning_tree(str)
        # Parse the spanning tree config options
        command = str.split(' ')
        case command[0]
        when "port"
            @current_interface[:spanning_tree_port_type] = command[2]
        when "guard"
            @current_interface[:spanning_tree_guard] = command[1]
        when "bpduguard"
            @current_interface[:bpduguard] = command[1]
        end
    end

    def p_config_interface_channel_group(str)
        # Is the port in a port channel?
        @current_interface[:channel_group] = str.split(' ')[0]

    end

    def e_config_interface
        @interfaces ||= {}
        @interfaces[@current_interface.delete(:id)] = @current_interface
    end
end
