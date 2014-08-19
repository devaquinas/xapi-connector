#Copyright (c) Piotr Gorzelany 2014

tls = require('tls')
dispatcher = require('./dispatcher.js')

print = (msg) ->
  console.log(msg + '\n')
  return


class Connector
  constructor: (@server_url, @conn_port, @stream_port, @username, @password) ->
    @conn = {}
    @stream = {}
    @msg = '' #this is required since data comes in chunks
    @msg_id = 0 #this will be used to uniquely identify a message
    @stream_msg = '' #this is for the stream
    @env =
      messages: {}

  buildCommand: (command, args, tag) ->
    @msg_id += 1
    com =
      command: if command? then command else throw new Error('Missing command')
      arguments: args if args?
    if tag? then com.customTag = tag else com.customTag = @msg_id.toString()
    @env.messages[@msg_id] = com #save the message and its id to the environment object
    return JSON.stringify(com)

  buildStreamCommand: (command, stream_session_id, symbols) ->
    com =
      command: if command? then command else throw new Error('Missing command')
    com.streamSessionId = stream_session_id if stream_session_id?
    com.symbols = symbols if symbols?
    return JSON.stringify(com)

  connect: () ->
    #establish tls connection and handlers
    @conn._socket = tls.connect(@conn_port, @server_url, @onOpen)
    @conn._socket.setEncoding('utf-8')
    @conn.dispatcher = new dispatcher(@conn._socket, 200)
    @conn.send = (msg) =>
      @conn.dispatcher.add(msg)
    @conn._socket.addListener('data', @onChunk)
    @conn._socket.addListener('error', @onError)
    @conn._socket.addListener('close', @onClose)
    @conn.end = () =>
      @conn._socket.end()
    return

  onChunk: (data) =>
    #since it is possible to receive multiple responses in one chunk, we have to split it
    #if the response is a partial msg we just add it to the @msg
    responses = data.split('\n\n')
    if responses.length == 1
      @msg += responses[0]
    else
      #if the responses contains multiple messages we send them to handler one by one
      responses = (res for res in data.split('\n\n') when res != '')
      for res in responses
        @msg += res
        @onMessage(@msg)
        @msg = ''
    return

  disconnect: () ->
    @conn.end()
    return

  connectStream: () ->
    @stream._socket = tls.connect(@stream_port, @server_url, @onStreamOpen)
    @stream._socket.setEncoding('utf-8')
    @stream.dispatcher = new dispatcher(@stream._socket, 200)
    @stream.send = (msg) =>
      @stream.dispatcher.add(msg)
    @stream._socket.addListener('data', @onStreamChunk)
    @stream._socket.addListener('error', @onStreamError)
    @stream._socket.addListener('close', @onStreamClose)
    @stream.end = () =>
      @stream._socket.end()
    return

  onStreamChunk: (data) =>
    #since it is possible to receive multiple responses in one chunk, we have to split it
    responses = data.split('\n\n')
    #partial response, just add the chunk
    if responses.length == 1
      @stream_msg += responses[0]
    #multiple responses, handle one by one
    else
      responses = (res for res in responses when res != '')
      for res in responses
        @stream_msg += res
        @onStreamMessage(@stream_msg)
        @stream_msg = ''
    return

    disconnectStream: () ->
      @stream.end()
      return

    #fill in onOpen, onMessage, onStreamOpen, onStreamMessage, onError and onStreamError handlers

module.exports = Connector
