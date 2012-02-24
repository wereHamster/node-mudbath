
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



# Middleware
# ----------

requireAuth = express.basicAuth.apply @, settings.basicAuth

fetchProjects = (req, res, next) ->
    Project.find {}, (err, projects) ->
        return next err if err
        req.projects = projects; next()

branchParam = (req, res, next) ->
    regexp = new RegExp req.params[0]
    if branch = req.project.refs.filter((b) -> b.name.match(regexp))[0]
        req.branch = branch; next()
    else
        next new Error 'No such branch'

fetchBranchBuilds = (req, res, next) ->
    query = { project: req.project._id, ref: req.params[0] }
    Build.find(query).sort('_id', -1).limit(5).exec (err, builds) ->
        return next err if err
        req.builds = builds; next()



# URL params
# ----------

app.param 'project', (req, res, next, id) ->
    Project.findById id, (err, project) ->
        if (err || !project)
            return next(err || new Error('Project ' + id + ' not found'))

        req.project = project; next();

app.param 'branch', (req, res, next, id) ->
    if branch = req.project.refs.filter((b) -> b.name.match(new RegExp(id)))[0]
        req.branch = branch; next()
    else
        next new Error 'Branch ' + id + ' not found'

app.param 'build', (req, res, next, id) ->
    Build.findById id, (err, build) ->
        if (err || !build)
            return next(err || new Error('Build ' + id + ' not found'))

        req.build = build; next();


createProject = (x, fn) ->
    project = new Project { _id: x.name, source: x.source.trim(), script: x.script }
    project.save (err) -> if err then fn err else fn null, project

triggerBuild = (payload) ->
    Project.findById payload.repository.name, (err, project) ->
        return if err || !project

        ref = payload.ref; commit = payload.commits[0]; timestamp = new Date
        if branch = project.branch ref
            branch.commit = commit
            branch.timestamp = timestamp
        else
            project.refs.push { name: ref, status: '', timestamp, commit }

        project.save ->
            build = new Build({ project: project._id, ref, commit })
            build.save ->
                enqueue build




# Here be the routes
# ------------------

app.get '/', fetchProjects, (req, res) ->
    res.render 'index', {
        title: 'continuous integration', subtitle: '',
        projects: req.projects, builds: [], displayProjectHeader: true
    }

# This is the endpoint where GitHub sends the post-receive payload. We trigger
# the build and reply with 200.
app.post '/hook', (req, res) ->
    triggerBuild JSON.parse req.body.payload; res.send 200

app.get '/new', (req, res) ->
    res.render 'new', { title: 'register new project', subtitle: '' }

app.post '/project', requireAuth, (req, res) ->
    createProject req.body, (err, project) ->
        res.redirect '/' + req.body.name

app.get '/:project', (req, res) ->
    res.render 'project', {
        title: "#{req.project._id}", project: req.project,
        subtitle: '', displayProjectHeader: false
    }

app.delete '/:project', requireAuth, (req, res) ->
    req.project.deleteCache()

    Build.remove { project: req.project._id }, ->
        Project.remove { _id: req.project._id }, ->
            res.redirect '/'

app.get '/:project/edit', requireAuth, (req, res) ->
    res.render 'project-edit', {
        title: "#{req.project._id}", subtitle: "edit",
        project: req.project
    }

app.post '/:project/edit', requireAuth, (req, res) ->
    req.project.set 'source', req.param 'source'
    req.project.set 'script', req.param('script').crlf()

    req.project.save -> res.redirect '/' + req.project._id

app.get '/:project/*', branchParam, fetchBranchBuilds, (req, res) ->
    res.render 'branch', {
        title: "#{req.project._id}", subtitle: "#{req.branch.name}",
        project: req.project, builds: req.builds
    }

app.delete '/:project/*', requireAuth, branchParam, (req, res) ->
    Build.remove { project: req.project._id, ref: req.branch.name }, ->
        req.branch.remove()
        req.project.save -> res.redirect '/' + req.project._id



# Start the web server.
app.listen parseInt(process.env.PORT) || 3000
