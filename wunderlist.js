// Wunderlist integration library node-js

var request = require('request');

// var accessToken;
var clientId = 'CLIENT_ID';
var basePath = 'WUNDERLIST_API_BASEPATH'
var headers;

function setup(token){
  headers = {
    "Content-Type": "application/json",
    "X-Access-Token": token,
    "X-Client-Id": clientId
  }
}

function getLists(){
  endPoint = '/lists';
  makeRequest(endPoint, 'GET', {});
}

function getListDetails(listId){
  endPoint = '/lists/' + listId;
  makeRequest(endPoint, 'GET', {});
}

function createList(title){
  endPoint = '/lists';
  makeRequest(endPoint, 'POST', {"title": title})
}

function deleteList(listId){
  revision =  WunderList.fetchRevision(listId);
  endPoint = '/lists/' + listId + "?revision=" + revision;
  makeRequest(endPoint, 'DELETE', {});
}

function getTasks(listId, status){
  endPoint = '/tasks?list_id=' + listId;
  if(status != undefined){
    endPoint = endPoint + '&completed=' + status;
  }
  makeRequest(endPoint, 'GET', {});
}

function getCompletedTasks(listId){
  getTasks(listId, true);
}

function getIncompleteTasks(listId){
  getTasks(listId, false)
}

function getTaskDetails(taskId){
  endPoint = '/tasks/' + taskId;
  makeRequest(endPoint, 'GET', {});
}

function createTask(listId, title){
  endPoint = '/tasks'
  data = {
    "list_id": listId,
    "title": title
  }
  makeRequest(endPoint, 'POST', data);
}

//Note - passing list id here will move task to the given list
function  updateTask(taskId, title, listId){
  endPoint = '/tasks/' + taskId;
  revision = WunderTask.getRevision(taskId);
  data = {
    "title": title,
    "revision": revision
  }
  if(listId != undefined){
    data.list_id = listId
  }
  makeRequest(endPoint, 'PATCH', data);

}

function  deleteTask(taskId){
  revision = WunderTask.getRevision(taskId);
  endPoint = '/tasks/' + taskId + '?revision=' + revision;
  makeRequest(endPoint, 'DELETE', {});
}

function makeRequest(endPoint, method, data){
  console.log(endPoint)
  url = basePath + endPoint
  options = {
    "url": url,
    "headers": headers,
    "method": method,
    "body": JSON.stringify(data)
  }
  request(options, function(err, resp, body){
    console.log(body);
  })
}
