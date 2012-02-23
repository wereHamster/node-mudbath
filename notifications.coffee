
settings = require './config'


# Email
# -----

email = require 'email'
email.from = "mudbath <mudbath@#{settings.email.domain}>"

exports.sendMail = (committer, subject, body, fn) ->
    to = [ settings.email.recipient, committer ]
    new email.Email({ to, subject, body }).send fn
