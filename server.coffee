https = require "https"
express = require "express"
app = express()

app.get '/', (req, res) ->
  getWatchers 'jisaacks', 'GitGutter', (users) ->
    console.log "#{users.length} users are watching"
    getOrgs users, (orgs) ->
      console.log "#{orgs.length} orgs are watching"
      resp = ''
      for org in orgs
        resp += "<div><img src=\"#{org.avatar_url}\"></div>"
      res.send resp
      

getOrgs = (users, callback) ->
  orgs = []
  done = 0
  for user in users
    path = user.organizations_url + "?client_id=#{process.env.OAUTH_CLIENT_ID}&client_secret=#{process.env.OAUTH_CLIENT_SECRET}"
    getJSON path, (data) ->
      Array::push.apply orgs, data if data.length
      done += 1
      if done == users.length
        callback orgs


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


app.listen 3000

console.log 'listening on port 3000'