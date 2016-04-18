name "prd"
description "The Production environment"
cookbook_versions({
                      "chef-windows-demo" => "= 0.2.18",
                  })
override_attributes ({
                        "environment" => "prd",
                    })