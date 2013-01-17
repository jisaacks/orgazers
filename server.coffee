fs      = require "fs"
jade    = require "jade"
express = require "express"
https   = require "https"
sockio  = require "socket.io"
statica = require "static-asset"
qrystr  = require "querystring"

app     = express()
port    = process.env.PORT or 5000
server  = app.listen port, -> console.log "Listening on " + port
io      = sockio.listen server

app.use statica(__dirname + "/public/")
app.use express.static(__dirname + "/public/")
app.use express.cookieParser()

cookies = {}

gotauth = ->
  return cookies.access_token?

authstr = ->
  if gotauth()
    "access_token=#{cookies.access_token}"
  else
    "client_id=#{process.env.OAUTH_CLIENT_ID}&client_secret=#{process.env.OAUTH_CLIENT_SECRET}"

app.get '/', (req, res) ->
  cookies = req.cookies
  fs.readFile './views/index.jade', (err, contents) ->
    throw err if err
    fn = jade.compile contents
    getRateLimit (data) ->
      if gotauth()
        limit = data.rate.limit
        remaining = data.rate.remaining
        getJSON "/user?#{authstr()}", (user) ->
          console.log user
          results = fn
            limit:        limit
            remaining:    remaining
            current_user: user
          res.send results
      else
        results = fn
          limit:        100
          remaining:    100
          current_user: false
        res.send results

app.get '/for', (req, res) ->
  cookies = req.cookies
  user    = req.query["user"]
  repo    = req.query["repo"]
  fs.readFile './views/for.jade', (err, contents) ->
    throw err if err
    fn = jade.compile contents
    results = fn
      user: user
      repo: repo
    res.send results

app.get '/oauth_callback', (req, resp) ->
  code = req.query["code"]
  options =
   host: 'github.com'
   port: 443
   path: '/login/oauth/access_token'
   method: 'POST'
  data = ''
  req = https.request options, (res) ->
    res.on 'data', (chunk) ->
      data += chunk
    res.on 'end', ->
      obj = qrystr.parse data
      access_token = obj.access_token
      token_type = obj.token_type
      resp.cookie 'access_token', access_token, expires: 0, httpOnly: true
      resp.writeHead 302, 'Location': '/'
      resp.end()
  req.on 'error', (e) ->
    console.log 'error', e.message
  req.write "#{authstr()}&code=#{code}"
  req.end()

app.get '/github', (req, res) ->
  url = 'https://github.com/login/oauth/authorize'
  url += "?client_id=#{process.env.OAUTH_CLIENT_ID}"
  res.writeHead 302, 'Location': url
  res.end()

app.get '/logout', (req, res) ->
  res.clearCookie 'access_token'
  res.writeHead 302, 'Location': '/'
  res.end()

io.configure -> 
  io.set "transports", ["xhr-polling"]
  io.set "polling duration", 10

io.sockets.on 'connection', (socket) ->
  socket.on 'for', (data) ->
    user = data.user
    repo = data.repo
    orgsCallback = (orgs) ->
      socket.emit 'finished', orgs: orgs
    orgStatusCallback = (count) ->
      socket.emit 'status', message: "Found #{count} orgs..."
    usersCallback = (users) ->
      if users.error
        socket.emit 'status', message: users.error
      else
        socket.emit 'status', message: "Found #{users.length} users..."
        getRateLimit (data) ->
          limit = data.rate.limit
          remaining = data.rate.remaining
          console.log "#{remaining} left of #{limit} API Requests Left"
          unless gotauth() or remaining < 100
            remaining = 100
          if remaining < users.length
            socket.emit 'status', message: "I do not have enough GitHub API Requests 
            to process this request. I have #{remaining} but I need #{users.length}. 
            Please try again later or use a repo with less stargazers."
          else
            getOrgs users, orgsCallback, orgStatusCallback
    usersStatusCallback = (count) ->
      socket.emit 'status', message: "Found #{count} users..."
    getWatchers user, repo, usersCallback, usersStatusCallback


getRateLimit = (callback) ->
  path = "/rate_limit?#{authstr()}"
  getJSON path, (data) ->
    callback data

getOrgs = (users, callback, statusCallback) ->
  orgs = []
  done = 0
  skipping = 0
  _orgs = (user) ->
    path = user.organizations_url + "?#{authstr()}"
    getJSON path, (data) ->
      if data.length
        org.user = user for org in data
        Array::push.apply orgs, data
        statusCallback orgs.length
      done += 1
      if done == users.length - skipping
        console.log "done"
        callback orgs
  for user in users
    if user.type == "User"
      _orgs user
    else
      skipping += 1
      if user.public_members_url
        user.user = login: user.login
        orgs.push user
      console.log "Skipping #{user.login}"


getWatchers = (user, repo, callback, statusCallback) ->
  users = []
  watchers = (page) ->
    path = "/repos/#{user}/#{repo}/watchers?per_page=100&page=#{page}&#{authstr()}"
    getJSON path, (data) ->
      if data.length
        if data.message and /API Rate Limit Exceeded/.test(data.message)
          # We have run out of API requests.
          callback error: "I am out of GitHub API requests. I can no longer process 
          this request at this time. Please try again later."
        else  
          Array::push.apply users, data
          statusCallback users.length
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
