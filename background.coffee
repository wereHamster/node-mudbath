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
    # project branch is marked as 'building'.
    perform: (id) ->
        Build.findById id, (err, build) =>
            Project.findById build.project, (err, project) =>
                branch = project.branch build.ref
                branch.status = build.status = 'building'
                build.save => project.save => @prepareBuild project, build


    # This is a wrapper around spawn. It stores all output (stdout and stderr)
    # in the build object.
    spawn: (project, build, cmd, args, opt, fn) ->
        proc = spawn cmd, args, opt

        output = (channel, data) ->
            build.output.push({ channel, text: '' + data }); build.save ->

        proc.stdout.on 'data', (data) -> output 'stdout', data
        proc.stderr.on 'data', (data) -> output 'stderr', data

        proc.on 'exit', (code) -> fn code


    # Build failures are sent by email to the committer. Email is good enough
    # for the time being.
    reportBuildFailure: (build) ->
        committer = build.pusherIdentity()
        subject = "Failure: #{build.project} - #{build.ref}"
        body = build.output.map((x) -> x.text).join ''
        sendMail committer, subject, body


    # When the build completes, store the branch status in the project. And if
    # the build failed, report the failure to whoever wants to know.
    didComplete: (project, build, code) ->
        build.deleteBuildArtifacts()

        branch = project.branch build.ref
        branch.status = build.status = code is 0 and 'success' or 'failure'
        branch.commit = build.commit

        build.save => project.save =>
            @complete(); @reportBuildFailure build if code isnt 0


    # This steps prepares the build directory, copies the code into a new
    # directory and all that stuff.
    prepareBuild: (project, build) ->
        args = [ __dirname, project._id, project.get('source'), build.id, build.commit.id ]
        @spawn project, build, './build.sh', args, {}, (code) =>
            if code is 0
                @runBuildScript project, build
            else
                @didComplete project, build, code


    # This runs the actual user-supplied script. In bash as the login shell.
    # So feel free to use all of the bash beauty you want.
    runBuildScript: (project, build) ->
        args = [ '-l', '-c', project.script ]; cwd = build.buildPath()
        @spawn project, build, 'bash', args, { cwd }, (code) =>
            @didComplete project, build, code


# Start the background worker.
(new mojo.Worker mojoConnection, [ Builder ]).poll()


# The only symbol we export is a function to enqueue a new build. So, without
# further ado, here it is:
exports.enqueue = (build) ->
    mojoConnection.enqueue Builder.name, build._id.toString(), ->
