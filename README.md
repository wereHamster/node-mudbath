
mudbath is a continuous integration server. Its main features are:

 - support for mutiple projects, and multiple branches in each project
 - stores build output in a database
 - ability to trigger builds from github post-receive hooks


Installation
------------

The server uses mongodb to store the project details and build output. Make
sure you have mongodb installed and running. The database is not configurable
at the momont, it'll always try to connect to localhost and use the database
`mudbath`.

    # Get the source code
    git clone git://github.com/wereHamster/mudbath.git
    cd mudbath

    # Install dependencies
    npm install

    # Configure some options
    cp config.coffee.template config.coffee
    $EDITOR config.coffee

    # Run the server
    ./node_modules/.bin/coffee app


Usage
-----

The web interface will run on port 3000 (use the `PORT` environment variable
to change that). First create a new project: http://localhost:3000/new. The
name **must** be the same as the project name on github. The source url should
point to the same repository. The script is executed in a bash login shell and
its exit code directly influences the success or failure of the build. All
output (stdout and stderr) of the script is captured and stored in the
database.


Example
-------

**name**: mudbath,
**source**: git://github.com/wereHamster/mudbath.git,
**script**:

    set -e
    npm install 1>/dev/null 2>&1
    make test


Gitolite
--------

It is possible to integrate mudbath with gitolite. You can use a [ruby
script][post-receive-mudbath] to send the build trigger from a post-receive
hook.

[post-receive-mudbath]: https://gist.github.com/4b8aefd534a30fba645e

Screenshots
-----------

### Main overview screen:

![screenshot-1](https://img.skitch.com/20120223-jewsuujx3gdyq9y97kqu9sq131.png)

### Detail of a project branch, with build output:

![screenshot-2](https://img.skitch.com/20120223-xkf6hk8k82d33qnqyrs9hyr9w9.png)


Used by
-------

This tool is currently in use by:
[rmx](http://rmx.im),
[kooaba](http://www.kooaba.com)
