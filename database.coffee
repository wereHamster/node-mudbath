wrench = require 'wrench'
{ html } = require './ansi'

# We use mongodb as the database, in particular the mongoose ODM which makes
# schema definitions quite easy to define.

mongoose = module.exports = require 'mongoose'
ObjectID = mongoose.Schema.ObjectId

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
# A project keeps a cache of all the refs that have been built. Each ref has
# a reference to the last build that was run.

RefSchema = new mongoose.Schema({
    name: { type: String }, build: { type: ObjectID }
})

RefSchema.methods =
    iso8601: -> iso8601 new Date @build.generationTime * 1000


ProjectSchema = new mongoose.Schema({
    _id: { type: String }, script: { type: String },
    refs: { type: [ RefSchema ] }
})

ProjectSchema.methods =
    cachePath:   -> __dirname + '/data/cache/' + @_id
    iso8601:     -> iso8601 new Date()

    findRef: (n) -> @refs.filter((x) -> x.name is n)[0]
    sortedRefs:  -> @refs.sort (x, y) ->
        (y.build.generationTime || 0) - (x.build.generationTime || 0)

    deleteCache: -> wrench.rmdirSyncRecursive @cachePath(), true

    # Delete a ref by its name. Is safe to call even if the ref doesn't exist.
    # Also deletes all related builds.
    deleteRefByName: (name, fn) ->
        if ref = @findRef name
            Build.remove { project: @_id, ref: name }, =>
                ref.remove(); @save fn
        else
            fn()

mongoose.model('Project', ProjectSchema);
Project = mongoose.model('Project');



# Build
# -----
#
# Each build knows the ref name, payload used to trigger it, and the output
# from the scripts. The output is not sanitezed, it's stored as-is.

OutputSchema = new mongoose.Schema({
    channel: { type: String }, text: { type: String }
})

BuildSchema = new mongoose.Schema({
    project: { type: String }, ref: { type: String }, payload: { type: {} },
    output: { type: [OutputSchema] }, status: { type: String }
})

BuildSchema.methods =
    buildPath: -> __dirname + '/data/builds/' + @_id
    iso8601:   -> iso8601 new Date @_id.generationTime * 1000
    html:      -> html @output.map((x) -> x.text).join('')
    deleteBuildArtifacts: -> wrench.rmdirSyncRecursive @buildPath(), true
    pusherIdentity: -> "#{@payload.pusher.name} <#{@payload.pusher.email}>"
    headCommit: -> @payload.head_commit
    numCommits: -> @payload.commits.length

mongoose.model('Build', BuildSchema);
Build = mongoose.model('Build');
