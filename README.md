# Windows Automation Demo

This demo includes the following top-level items:

## Rackspace Public Cloud Orchestration

* Create, scale, destroy environments

## Windows Server Bootstrapping and Configuration Management

* With Chef for Windows via Jenkins-based callbacks
* With Powershell DSC

## .NET Web Application Continuous Integration

* Using Jenkins on Windows, MSBuild, and NUnit

## .NET Web Application Automation Deployment

* Using Jenkins on Windows with MS Web Deploy

# How to use the demo

## The Application

The .NET Web Application is a lightly-modified version of the Visual Studio 2013 sample MVC app:

* https://github.com/iskandar/aspnet-mvc-sample


## Jenkins

You'll want to use Jenkins as the frontend to allow for centralised history, logging, and control.

Iskandar has a Jenkins Master server running Linux and a Jenkins Node on Windows. 
You only need the Windows Jenkins Node for this project.

## Command line

### `create-environment.py`

### `scale-environment.py`

### `destroy-environment.py`


