#
# Cookbook Name:: collectd
# Recipe:: default
#
# Copyright 2010, Atari, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package "collectd" do
  case node[:platform]
  when "centos","redhat","fedora","suse","scientific","amazon"
    package_name "collectd"
  when "debian","ubuntu"
    package_name "collectd-core"
    options "--force-yes"
  end
  action :install
end

#WT custom modification to the base recipe:
#If this is a RH based distro then install the collectd-java plugin since it's installed by default in ubuntu.
if platform?("centos","redhat","fedora","suse")
  # WT's collectd-java RPM requires that libjvm.so is accessable. So we need to setup a symlink if this file exists.
  # Create a symbolic link to libjvm.so so the collectd java/jmx plugin works properly.
  link "/usr/lib64/libjvm.so" do
    to "/usr/lib/jvm/java/jre/lib/amd64/server/libjvm.so"
	only_if "test -f /usr/lib/jvm/java/jre/lib/amd64/server/libjvm.so"
  end
  package "collectd-java" do
    package_name "collectd-java"
    action [:install]
  end
else
  # do nothing
end

#WT custom modification to the base recipe:
# WT's collectd custom DEB requires that libjvm.so is accessable. So we need to setup a symlink if this file exists.
if platform?("debian","ubuntu")
  # Create a symbolic link to libjvm.so so the collectd java/jmx plugin works properly.
  link "/usr/lib/libjvm.so" do
    to "/usr/lib/jvm/default-java/jre/lib/amd64/server/libjvm.so"
	only_if "test -f /usr/lib/jvm/default-java/jre/lib/amd64/server/libjvm.so"
  end
else
  # do nothing
end

service "collectd" do
  supports :restart => true, :status => true
end

ruby_block "edit init script" do
  block do
    case node[:platform]
    when "centos","redhat","fedora","suse"
      rc = Chef::Util::FileEdit.new("/etc/rc.d/init.d/collectd")
      rc.search_file_replace_line("CONFIG=", "CONFIG=#{node[:collectd][:conf_dir]}/collectd.conf")
      rc.write_file
    when "debian","ubuntu"
      rc = Chef::Util::FileEdit.new("/etc/init.d/collectd")
      rc.search_file_replace_line("CONFIGFILE=", "CONFIGFILE=#{node[:collectd][:conf_dir]}/collectd.conf")
      rc.write_file
    end
  end
end

directory node[:collectd][:conf_dir] do
  owner "root"
  group "root"
  mode  00755
end

directory node[:collectd][:plugin_conf_dir] do
  owner "root"
  group "root"
  mode 00755
end

directory node[:collectd][:base_dir] do
  owner "root"
  group "root"
  mode 00755
  recursive true
end

directory node[:collectd][:plugin_dir] do
  owner "root"
  group "root"
  mode 00755
  recursive true
end

%w(collectd collection thresholds).each do |file|
  template "#{node[:collectd][:conf_dir]}/#{file}.conf" do
    source "#{file}.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, resources(:service => "collectd")
  end
end

ruby_block "delete_old_plugins" do
  block do
    Dir['#{node[:collectd][:plugin_conf_dir]}/*.conf'].each do |path|
      autogen = false
      File.open(path).each_line do |line|
        if line.start_with?('#') and line.include?('autogenerated')
          autogen = true
          break
        end
      end
      if autogen
        begin
          resources(:template => path)
        rescue ArgumentError
          # If the file is autogenerated and has no template it has likely been removed from the run list
          Chef::Log.info("Deleting old plugin config in #{path}")
          File.unlink(path)
        end
      end
    end
  end
end

service "collectd" do
  action [:enable, :start]
end
