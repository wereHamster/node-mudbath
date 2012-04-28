{ spawn } = require 'child_process'
{ sendMail } = require './notifications'

# Builds are run in the background. We use mojo, the mongodb job queue to
# manage the background jobs.

mongoose = require './database'
Project  = mongoose.model 'Project'
Build    = mongoose.model 'Build'


mojo = require 'mojo'
mojoConnection = new mojo.Connection db: 'mudbath'


# The builder job clones the code into a fresh directory and runs the project
# script in it. After doing some preparations and stuff. If the build fails it
# sends notifications.
class Builder extends mojo.Template

    # Get both the build and project and then kick of the whole process. The
    # build status is set to 'building'.
    perform: (id) ->
        Build.findById id, (err, build) =>
            Project.findById build.project, (err, project) =>
                build.status = 'building'
                build.save => @prepareBuild project, build


    # This is a wrapper around spawn. It stores all output (stdout and stderr)
    # in the build object.
    spawn: (build, cmd, args, opt, fn) ->
        proc = spawn cmd, args, opt

        output = (channel, data) ->
            build.output.push({ channel, text: '' + data }); build.save ->

        proc.stdout.on 'data', (data) -> output 'stdout', data
        proc.stderr.on 'data', (data) -> output 'stderr', data

        proc.on 'exit', (code) -> fn code


    # Build failures are sent by email to the committer. Email is good enough
    # for the time being.
    reportBuildFailure: (build) ->
        committer = build.pusherIdentity() || build.headCommitterIdentity()
        subject = "Failure: #{build.project} - #{build.ref}"
        body = build.output.map((x) -> x.text).join ''
        sendMail committer, subject, body


    # When the build completes, update the build status. And if the build
    # failed, report the failure to whoever wants to know.
    didComplete: (build, code) ->
        build.deleteBuildArtifacts()

        build.status = code is 0 and 'success' or 'failure'
        build.save => @complete(); @reportBuildFailure build if code isnt 0


    # This steps prepares the build directory, copies the code into a new
    # directory and all that stuff.
    prepareBuild: (project, build) ->
        args = [ __dirname, project._id, project.get('source'), build.id, build.headCommit().id ]
        @spawn build, './build.sh', args, {}, (code) =>
            if code is 0
                @runBuildScript project, build
            else
                @didComplete build, code


    # This runs the actual user-supplied script. In bash as the login shell.
    # So feel free to use all of the bash beauty you want.
    runBuildScript: (project, build) ->
        args = [ '-l', '-c', project.script ]; cwd = build.buildPath()
        @spawn build, 'bash', args, { cwd }, (code) =>
            @didComplete build, code


# Start the background worker.
(new mojo.Worker mojoConnection, [ Builder ]).poll()


# The only symbol we export is a function to enqueue a new build. So, without
# further ado, here it is:
exports.enqueue = (build) ->
    mojoConnection.enqueue Builder.name, build._id.toString(), ->
