name "web"
description "A base web server role with IIS and .NET 4.5"
run_list "recipe[iis::mod_aspnet45]", "recipe[chef-windows-demo]"
