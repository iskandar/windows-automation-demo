import hudson.model.*
import groovy.json.*

def currentBuild = Thread.currentThread().executable
def resolver = currentBuild.buildVariableResolver
def downstreamJobName = resolver.resolve("DOWNSTREAM_JOB_NAME")
def jobNumber = currentBuild.getNumber()

def cause = new Cause.UpstreamCause(currentBuild)
def causeAction = new CauseAction(cause)
def downstreamJob = Hudson.instance.getItemByFullName(downstreamJobName)
println ""
println "Downstream Job: " + downstreamJob.inspect()

// Read JSON node list
def jsonFile = currentBuild.workspace.toString() + '/nodes-' + jobNumber + '.json'
def jsonSlurper = new JsonSlurper()
String fileContents = new File(jsonFile).getText('UTF-8')
def nodeList = jsonSlurper.parseText(fileContents)
println "Got nodes: " + nodeList.inspect()

println ""
println "----"
nodeList.each { node ->
    def params = [
            new StringParameterValue('NODE_IP', node["ip"]),
            new StringParameterValue('NODE_NAME', node["name"]),
    ]
    if (resolver.resolve("NAMESPACE")) {
        params << new StringParameterValue('NAMESPACE', resolver.resolve("NAMESPACE"))
    }
    if (resolver.resolve("ENVIRONMENT")) {
        params << new StringParameterValue('ENVIRONMENT', resolver.resolve("ENVIRONMENT"))
    }
    if (resolver.resolve("BUILD_SELECTOR")) {
        params << new StringParameterValue('BUILD_SELECTOR', resolver.resolve("BUILD_SELECTOR"))
    }
    println "Calling " + downstreamJobName + " with params " + params.inspect()
    Hudson.instance.queue.schedule(downstreamJob, 0, causeAction, new ParametersAction(params))
}
println "----"

println ""
println "Removing file: " + jsonFile
new File(jsonFile).delete()

println ""
println "Done"