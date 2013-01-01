https = require "https"
express = require "express"
fs = require "fs"
jade = require "jade"
app = express()

app.get '/', (req, res) ->
  fs.readFile './form.jade', (err, contents) ->
    throw err if err
    fn = jade.compile contents
    results = fn()
    res.send results

app.get '/for', (req, res) ->
  user = req.query["user"]
  repo = req.query["repo"]
  getWatchers user, repo, (users) ->
    console.log "#{users.length} users are watching"
    getRateLimit (data) ->
      limit = data.rate.limit
      remaining = data.rate.remaining
      console.log "#{remaining} left of #{limit} API Requests Left"
      if remaining < users.length
        res.send "I do not have enough GitHub API Requests to process this request. I have #{remaining} but I need #{users.length}. Please try again later or use a repo with less stargazers."
      else
        getOrgs users, (orgs) ->
          console.log "#{orgs.length} orgs are watching"
          resp = ''
          for org in orgs
            resp += "<a href=\"https://github.com/#{org.user.login}\"><img title=\"#{org.login}\" width=\"80\" height=\"80\" src=\"#{org.avatar_url}\"></a>"
          res.send "<body style=\"margin: 0\">#{resp}</body>"


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


port = process.env.PORT or 5000
app.listen port, ->
  console.log "Listening on " + port