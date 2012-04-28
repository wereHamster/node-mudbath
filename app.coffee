
{ statSync } = require 'fs'
{ existsSync } = require 'path'

settings = require './config'



# Trim removes leading and trailing whitespace, clrf replaces clrf with lf.
String::trim = -> @replace /^\s+|\s+$/g, ''
String::crlf = -> @replace /\r\n/g, '\n'



# Database
mongoose = require './database'
Project  = mongoose.model 'Project'
Build    = mongoose.model 'Build'



# Background worker
{ enqueue } = require './background'



# Express setup
# -------------

express = require 'express'
app = express.createServer()
app.set 'view engine', 'jade'

stylus = require 'stylus'
compile = (str, path) ->
    stylus(str).set('filename', path).set('warn', true)

app.configure ->
    app.use express.logger()

    src = dst = __dirname + '/public'
    app.use stylus.middleware { src, dst, compile }

    app.use express.static __dirname + '/public'
    app.use express.bodyParser()

app.configure 'development', ->
    app.use express.errorHandler { dumpExceptions: true, showStack: true }


renderError = (req, res, code) ->
    res.render 'error', { title: 'error', subtitle: '', code }


# Middleware
# ----------

requireAuth = express.basicAuth.apply @, settings.basicAuth

fetchProjects = (req, res, next) ->
    Project.find {}, (err, projects) ->
        return renderError req, res, 500 if err
        req.projects = projects

        ids = projects.map (x) -> x.refs.map (x) -> x.build
        ids = Array.prototype.concat.apply [], ids
        Build.find { _id: { $in: ids } }, (err, builds) ->
            return renderError req, res, 500 if err
            req.builds = builds; next()

refParam = (req, res, next) ->
    if ref = req.project.findRef req.params[0]
        req.ref = ref; next()
    else
        return renderError req, res, 404

fetchLatestBuilds = (req, res, next) ->
    ids = req.project.refs.map (x) -> x.build
    Build.find { _id: { $in: ids } }, (err, builds) ->
        return renderError req, res, 500 if err
        req.builds = builds; next()

fetchRefBuilds = (req, res, next) ->
    query = { project: req.project._id, ref: req.params[0] }
    Build.find(query).sort('_id', -1).limit(5).exec (err, builds) ->
        return renderError req, res, 404 if err
        req.builds = builds; next()



# URL params
# ----------

app.param 'project', (req, res, next, id) ->
    Project.findById id, (err, project) ->
        if (err || !project)
            return renderError req, res, 404

        req.project = project; next();

app.param 'build', (req, res, next, id) ->
    Build.findById id, (err, build) ->
        if (err || !build)
            return renderError req, res, 404

        req.build = build; next();



# Helpers
# -------

createProject = (x, fn) ->
    project = new Project { _id: x.name, source: x.source, script: x.script }
    project.save (err) -> if err then fn err else fn null, project


deleteRef = (repoName, ref) ->
    Project.findById repoName, (err, project) ->
        if project then project.deleteRefByName ref, ->


triggerBuild = (repoName, name, payload) ->
    Project.findById repoName, (err, project) ->
        return if err || !project

        build = new Build({ project: project._id, ref: name, payload })
        build.save ->
            if ref = project.findRef name
                ref.build = build.id
            else
                project.refs.push { name, build: build.id }

            project.save -> enqueue build


nullSHA = [1..40].map((x) -> '0').join ('')
processHookPayload = (x) ->
    if x.after is nullSHA
        deleteRef x.repository.name, x.ref
    else if x.ref.match /^refs\/heads\//
        triggerBuild x.repository.name, x.ref, x


findBuild = (req) ->
    (id) -> req.builds.filter((x) -> x.id.toString() is id.toString())[0]



# Here be the routes
# ------------------

app.get '/', fetchProjects, (req, res) ->
    res.render 'index', {
        title: 'continuous integration', subtitle: '',
        projects: req.projects, displayProjectHeader: true, build: findBuild(req)
    }

# This is the endpoint where GitHub sends the post-receive payload. We trigger
# the build and reply with 200.
app.post '/hook', (req, res) ->
    processHookPayload JSON.parse req.body.payload; res.send 200

app.get '/new', requireAuth, (req, res) ->
    res.render 'new', { title: 'register new project', subtitle: '' }

app.post '/project', requireAuth, (req, res) ->
    createProject req.body, (err, project) ->
        if err
            res.redirect '/new'
        else
            res.redirect '/' + req.body.name

app.get '/:project', fetchLatestBuilds, (req, res) ->
    res.render 'project', {
        title: "#{req.project._id}", project: req.project,
        subtitle: '', displayProjectHeader: false, build: findBuild(req)
    }

app.post '/:project/delete', requireAuth, (req, res) ->
    req.project.deleteCache()

    Build.remove { project: req.project._id }, ->
        Project.remove { _id: req.project._id }, ->
            res.redirect '/'

app.get '/:project/edit', requireAuth, (req, res) ->
    res.render 'project-edit', {
        title: "#{req.project._id}", subtitle: "edit",
        project: req.project, build: (id) ->
            req.builds.filter((x) -> x.id.toString() is id.toString())[0]
    }

app.post '/:project/edit', requireAuth, (req, res) ->
    req.project.set 'source', req.param 'source'
    req.project.set 'script', req.param 'script'

    req.project.save -> res.redirect '/' + req.project._id

app.get '/:project/*', refParam, fetchRefBuilds, (req, res) ->
    res.render 'ref', {
        title: "#{req.project._id}", subtitle: "#{req.ref.name}",
        project: req.project, builds: req.builds
    }

app.delete '/:project/*', requireAuth, (req, res) ->
    req.project.deleteRefByName req.params[0], ->
        res.redirect '/' + req.project._id



# Start the web server.
app.listen parseInt(process.env.PORT) || 3000
