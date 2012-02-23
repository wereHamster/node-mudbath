wrench = require 'wrench'

# We use mongodb as the database, in particular the mongoose ODM which makes
# schema definitions quite easy to define.

mongoose = module.exports = require 'mongoose'
mongoose.connect 'mongodb://localhost/mudbath'


# Convert a javascript Date into a string in ISO8601 format.
iso8601 = (d) ->
    pad = (n) -> n < 10 and '0'+n or n
    date = [d.getUTCFullYear(), pad(d.getUTCMonth()+1), pad(d.getUTCDate())]
    time = [pad(d.getUTCHours()), pad(d.getUTCMinutes()), pad(d.getUTCSeconds())]
    return "#{date.join('-')}T#{time.join(':')}Z"


# Project
# -------
#
# A project keeps a cache of all the refs that have been built, and for each
# ref the last commit and build status.

RefSchema = new mongoose.Schema({
    name: { type: String }, status: { type: String },
    timestamp: { type: Date }, commit: { type: {} }
})

RefSchema.methods =
    iso8601: -> iso8601 @timestamp

ProjectSchema = new mongoose.Schema({
    _id: { type: String }, script: { type: String },
    refs: { type: [ RefSchema ] }
})

{ html } = require './ansi'
ProjectSchema.methods =
    cachePath:   -> __dirname + '/data/cache/' + @_id
    iso8601:     -> iso8601 new Date()
    branch:  (n) -> @refs.filter((x) -> x.name is n)[0]
    deleteCache: -> wrench.rmdirSyncRecursive @cachePath(), true

mongoose.model('Project', ProjectSchema);
Project = mongoose.model('Project');


# Build
# -----
#
# Each build knows the ref name, commit and the output from the build scripts.

OutputSchema = new mongoose.Schema({
    channel: { type: String }, text: { type: String }
})

BuildSchema = new mongoose.Schema({
    project: { type: String }, ref: { type: String }, commit: { type: {} },
    output: { type: [OutputSchema] }, status: { type: String }
})

BuildSchema.methods =
    buildPath: -> __dirname + '/data/builds/' + @_id
    iso8601:   -> iso8601 new Date @_id.generationTime * 1000
    html:      -> html @output.map((x) -> x.text).join('')
    deleteBuildArtifacts: ->
        wrench.rmdirSyncRecursive @buildPath(), true
    committerIdentity: ->
        "#{@commit.committer.name} <#{@commit.committer.email}>"

mongoose.model('Build', BuildSchema);
Build = mongoose.model('Build');
