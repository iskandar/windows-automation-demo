#
# Cookbook Name:: chef-windows-demo
# Recipe:: default
#
#

# Stop the default site
iis_site 'Default Web Site' do
  action [:stop]
end

# Set up logging
# directory "C:\\logs" do
#   action :create
# end
# iis_config "/section:system.applicationHost/sites /siteDefaults.logfile.directory:\"C:\\logs\"" do
#   action :set
# end
#
# # Write to a file
# file "C:\\logs\\test.txt" do
#   content 'Here is some test text'
# end

# Add a registry key
# registry_key 'HKEY_LOCAL_MACHINE\SOFTWARE\CHEF_WINDOWS_DEMO' do
#   values [{
#               :name => 'HELLO',
#               :type => :expand_string,
#               :data => 'OMG WTF BBQ'
#           }]
#   action :create
#   # action :delete
# end

# Start a service
service 'w32time' do
  action [:enable, :start]
  # action [:disable, :stop]
end

# Create a new directory.
# We want this to be empty so our Load Balancer does not add this node into rotation.
directory "#{node['iis']['docroot']}\\WebApplication1" do
  action :create
end

# Write to a file
# file "#{node['iis']['docroot']}\\WebApplication1\\data.txt" do
#   item =  data_bag_item('bag1', 'item1')
#   content node.chef_environment + ' -_- '  + item['attr1']
# end

# Create a new IIS Pool
iis_pool 'WebApplication1' do
  runtime_version "4.0"
  pipeline_mode :Integrated
  pool_identity :ApplicationPoolIdentity
  start_mode :AlwaysRunning
  auto_start true
  load_user_profile true
  action :add
end

# Create a new IIS site
iis_site 'WebApplication1' do
  protocol :http
  port 80
  path "#{node['iis']['docroot']}\\WebApplication1"
  application_pool 'WebApplication1'
  action [:add,:start]
end

# Start the WWW Publishing Service
service 'w3svc' do
  action [:enable, :start]
end

# Install the Web Platform Installer
include_recipe 'webpi'

# Install the WebDeploy server package
webpi_product 'WDeployPS' do
  accept_eula true
  action :install
end
