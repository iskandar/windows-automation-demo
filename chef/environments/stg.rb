name "stg"
description "The Staging environment"
cookbook_versions({
                      "chef-windows-demo" => ">= 0.0.0",
                  })
override_attributes ({
                        "environment" => "stg",
                    })