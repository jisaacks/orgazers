fs      = require "fs"
jade    = require "jade"
express = require "express"
https   = require "https"
sockio  = require "socket.io"
statica = require('static-asset')

app     = express()
port    = process.env.PORT or 5000
server  = app.listen port, -> console.log "Listening on " + port
io      = sockio.listen server

app.use statica("/public/")

app.get '/', (req, res) ->
  fs.readFile './views/index.jade', (err, contents) ->
    throw err if err
    fn = jade.compile contents
    results = fn()
    res.send results

app.get '/for', (req, res) ->
  user = req.query["user"]
  repo = req.query["repo"]
  fs.readFile './views/for.jade', (err, contents) ->
    throw err if err
    fn = jade.compile contents
    results = fn
      user: user
      repo: repo
    res.send results

io.sockets.on 'connection', (socket) ->
  socket.on 'for', (data) ->
    user = data.user
    repo = data.repo
    getWatchers user, repo, (users) ->
      if users.error
        socket.emit 'status', message: users.error
      else
        socket.emit 'status', message: "Found #{users.length} users..."
        getRateLimit (data) ->
          limit = data.rate.limit
          remaining = data.rate.remaining
          console.log "#{remaining} left of #{limit} API Requests Left"
          if remaining < users.length
            socket.emit 'status', message: "I do not have enough GitHub API Requests to process this request. I have #{remaining} but I need #{users.length}. Please try again later or use a repo with less stargazers."
          else
            getOrgs users, (orgs) ->
              socket.emit 'finished', orgs: orgs


getRateLimit = (callback) ->
  path = "/rate_limit?client_id=#{process.env.OAUTH_CLIENT_ID}&client_secret=#{process.env.OAUTH_CLIENT_SECRET}"
  getJSON path, (data) ->
    callback data

getOrgs = (users, callback) ->
  orgs = []
  done = 0
  _orgs = (user) ->
    path = user.organizations_url + "?client_id=#{process.env.OAUTH_CLIENT_ID}&client_secret=#{process.env.OAUTH_CLIENT_SECRET}"
    getJSON path, (data) ->
      if data.length
        org.user = user for org in data
        Array::push.apply orgs, data
      done += 1
      if done == users.length
        callback orgs
  _orgs user for user in users


getWatchers = (user, repo, callback) ->
  users = []
  watchers = (page) ->
    path = "/repos/#{user}/#{repo}/watchers?per_page=100&page=#{page}&client_id=#{process.env.OAUTH_CLIENT_ID}&client_secret=#{process.env.OAUTH_CLIENT_SECRET}"
    getJSON path, (data) ->
      if data.length
        if data.message and /API Rate Limit Exceeded/.test(data.message)
          # We have run out of API requests.
          callback error: "I am out of GitHub API requests. I can no longer process this request at this time. Please try again later."
        else  
          Array::push.apply users, data
          watchers(page+1)
      else
        callback(users)
  watchers(1)
  

getJSON = (path, callback) ->
  data = ''
  options =
    host: 'api.github.com'
    port: 443
    path: path
  req = https.get options, (res) ->
    res.on 'data', (chunk) ->
      data += chunk
    res.on 'end', ->
      json_data = JSON.parse(data);
      callback json_data
  req.on 'error', (e) ->
    console.log 'error', e.message
