// Common service handler which would direct request to appropriate service

var Wunderlist = require('./wunderlist');
var User = require('../models/user');
var Facebook = require('./facebookService');
var Twitter = require('./twitter');
var GulfNewsRss = require('./gulfNewsRss');
var Salik = require('./salik');
var CarMaintenance = require('./carMaintenance');
var Q = require('q');

var wunderlistServices = ['note_delete', 'notes_create', 'notes_read', 'notes_update', 'list_delete', 'lists_read', 'lists_create', 'lists_update'];
var facebookServices = ['facebook'];
var twitterServices = ['twitter'];
var request, serviceClass;
var serviceConf = {}

exports.setup = function(req){
  request = req;
}

exports.determineService = function(){
  var params = request.body.result.parameters
  setServiceConf(params);
}

exports.performService = function(){
  var deferred = Q.defer();
  User.findOne({username: serviceConf.email})
	.then(function(user){
		if(!user){
      var errMessage = 'User not found';
      deferred.reject(errMessage);
    }else{
      return serviceClass.performService(serviceConf, user)
    }
	}).then(function(resp){
    deferred.resolve(resp);
  }).catch(function(err){
    deferred.reject(err);
  })
  return deferred.promise;
}

function setServiceConf(params){
  if(params['facebook'] != undefined)
    setFacebookServiceConf(params);
  if(params['twitter'] != undefined)
    setTwitterServiceConf(params);
  if(params['list'] != undefined)
    setWunderlistServiceConf(params);
  if(params['news'] != undefined)
    setGulfNewsServiceConf(params);
  if(params['SALIK'] != undefined)
    setupSalikServiceConf(params);
  if(params['CarService'] != undefined)
    setupCarMaintenanceConf(params);
  if(params['RTAParking'] != undefined)
    setupRtaParkingConf(params);
}

function setFacebookServiceConf(params){
  serviceClass = Facebook;
  serviceConf = {
    email: request.body['sessionId'],
    content: params['content']
  };
}

function setTwitterServiceConf(params){
  serviceClass = Twitter;
  serviceConf = {
    email: request.body['sessionId'],
    content: params['content']
  }
}

function setWunderlistServiceConf(params){
  var conf = {
    email: request.body['sessionId']
  };
  serviceClass = Wunderlist;
  if(params['list'] != '' && params['list'] != undefined){
    conf.list = params['list'];
  } else {
    conf.list = 'DefaultBot';
  }
  conf.content = params['content'];
  conf.services = []
  for(var i = 0; i < wunderlistServices.length; i++){
    var service = wunderlistServices[i];
    if(params[service] != '' && params[service] != undefined){
      conf.services.push(service)
      conf.service = service;
    }
  }
  serviceConf = conf;
}

function setGulfNewsServiceConf(params){
  serviceConf = {
    email: request.body['sessionId']
  }
  serviceClass = GulfNewsRss;
}

function setupSalikServiceConf(params){
  serviceConf = {
    email: request.body['sessionId'],
    car: params['Car'],
    service: 'topup',
    amount: params['number']
  }
  serviceClass = Salik;
}

function setupCarMaintenanceConf(params){
  console.log('car maintenance setup')
  serviceConf = {
    email: request.body['sessionId'],
    car: params['Car'],
    serviceDate: params['date']
  };
  serviceClass = CarMaintenance;
}

function setupRtaParkingConf(params){
  serviceConf = {
    email: request.body['sessionId'],
    car: params['Car'],
    duration: params['number'],
    service: 'bookParking',
    lat: params['lat'],
    lng: params['lng']
  };
  serviceClass = Salik;
}
