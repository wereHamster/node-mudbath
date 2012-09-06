{ request } = require 'https'

settings = require './config'
{ plain } = require './ansi'


# Email
# -----

email = require 'email'
email.from = "mudbath <mudbath@#{settings.email.domain}>"

exports.sendMail = (committer, subject, body, fn) ->
    to = [ settings.email.recipient, committer ]
    new email.Email({ to, subject, body: plain body }).send fn


exports.updateGithubStatus = (repo, sha, state, fn) ->
    # We can update the status on github only if we have a github api token.
    return unless settings.githubToken

    # The value of the Authorization header. Token is provided by the
    # settings.
    authorization = "token " + settings.githubToken

    # Request body, stringified JSON. We need to generate it here so we can
    # properly set the Content-Length header.
    body = JSON.stringify { state }

    headers =
        "Authorization":  authorization
        "Content-Length": body.length
        "Content-Type":   "application/json"
        "Host":           "api.github.com"

    options =
        host: 'api.github.com'
        port: 443
        path: "/repos/#{repo}/statuses/#{sha}"
        headers: headers
        method: 'POST'

    req = request options
    req.end body

    # Ignore response. Eventually we may want to check whether the request
    # was sent successfully and display some indication in our UI.
