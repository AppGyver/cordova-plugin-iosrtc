import Foundation
import AVFoundation


class iosrtcPluginSingleton {
    
    static let sharedInstance = iosrtcPluginSingleton()
    
    // RTCPeerConnectionFactory single instance.
    var rtcPeerConnectionFactory: RTCPeerConnectionFactory!
    // Single PluginGetUserMedia instance.
    var pluginGetUserMedia: PluginGetUserMedia!
    // PluginRTCPeerConnection dictionary.
    var pluginRTCPeerConnections: [Int : PluginRTCPeerConnection]!
    // PluginMediaStream dictionary.
    var pluginMediaStreams: [String : PluginMediaStream]!
    // PluginMediaStreamTrack dictionary.
    var pluginMediaStreamTracks: [String : PluginMediaStreamTrack]!
    // PluginMediaStreamRenderer dictionary.
    var pluginMediaStreamRenderers: [Int : PluginMediaStreamRenderer]!
    // Dispatch queue for serial operations.
    var queue: dispatch_queue_t!
    
    func newConnection(pcId:Int, pcConfig:NSDictionary?, pcConstraints:NSDictionary?, eventListener: (data: NSDictionary) -> Void) {
        
        let pluginRTCPeerConnection = PluginRTCPeerConnection(
            rtcPeerConnectionFactory: self.rtcPeerConnectionFactory,
            pcConfig: pcConfig,
            pcConstraints: pcConstraints,
            eventListener: { (data: NSDictionary) -> Void in
                eventListener(data: data)
            },
            eventListenerForAddStream: self.saveMediaStream,
            eventListenerForRemoveStream: self.deleteMediaStream
        )
        
        // Store the pluginRTCPeerConnection into the dictionary.
        self.pluginRTCPeerConnections[pcId] = pluginRTCPeerConnection
        
        // Run it.
        pluginRTCPeerConnection.run()
    }
    
    
    init() {
        
        print("iosrtcPluginSingleton  -> pluginInitialize()");
        
        pluginMediaStreams = [:]
        pluginMediaStreamTracks = [:]
        pluginMediaStreamRenderers = [:]
        queue = dispatch_queue_create("cordova-plugin-iosrtc", DISPATCH_QUEUE_SERIAL)
        pluginRTCPeerConnections = [:]
        
        // Initialize DTLS stuff.
        RTCPeerConnectionFactory.initializeSSL()
        
        // Create a RTCPeerConnectionFactory.
        self.rtcPeerConnectionFactory = RTCPeerConnectionFactory()
        
        // Create a PluginGetUserMedia instance.
        self.pluginGetUserMedia = PluginGetUserMedia(
            rtcPeerConnectionFactory: rtcPeerConnectionFactory
        )
        
    }
    
    deinit {
    
    }
    
    func createOffer(pcId:Int, options: NSDictionary?, onData: (data: NSDictionary) -> Void, onError: (error: NSError) -> Void) {
        dispatchWithConnection(pcId) { connection in
            connection.createOffer(options, callback: onData, errback: onError)
        }
    }
    
    func createAnswer(pcId:Int, options: NSDictionary?, onData: (data: NSDictionary) -> Void, onError: (error: NSError) -> Void) {
        dispatchWithConnection(pcId) { connection in
            connection.createAnswer(options, callback: onData, errback: onError)
        }
    }
    
    func setLocalDescription(pcId:Int, desc: NSDictionary, onData: (data: NSDictionary) -> Void, onError: (error: NSError) -> Void) {
        dispatchWithConnection(pcId) { connection in
            connection.setLocalDescription(desc, callback: onData, errback: onError)
        }
    }
    
    func setRemoteDescription(pcId:Int, desc: NSDictionary, onData: (data: NSDictionary) -> Void, onError: (error: NSError) -> Void) {
        
        dispatchWithConnection(pcId) { connection in
            connection.setRemoteDescription(desc, callback: onData, errback: onError)
        }
    }
    
    func addIceCandidate(pcId:Int, candidate: NSDictionary, onData: (data: NSDictionary) -> Void, onError: (error: NSError) -> Void) {
        
        dispatchWithConnection(pcId) { connection in
            connection.addIceCandidate(candidate, callback: onData, errback: onError)
        }
    }
    
    func addStream(pcId:Int, streamId:String) {
        dispatchWithConnectionAndMediaStream(pcId, streamId: streamId) { (connection, mediaStream) in
            if connection.addStream(mediaStream) == true {
                self.saveMediaStream(mediaStream)
            }
        }
    }
    
    func removeStream(pcId:Int, streamId:String) {
        if let mediaStream = getMediaStream(streamId) {
            dispatchWithConnection(pcId) { connection in
                connection.removeStream(mediaStream)
            }
        }
    }
    
    func createDataChannel(pcId:Int, dcId:Int, label:String, options:NSDictionary, onData: (data: NSDictionary) -> Void, onBinaryMessage: (data: NSData) -> Void) {
        dispatchWithConnection(pcId) { connection in
            connection.createDataChannel(dcId,
                                         label: label,
                                         options: options,
                                         eventListener: onData,
                                         eventListenerForBinaryMessage: onBinaryMessage
            )
        }
    }
    
    func getRTCPeerConnection(pcId:Int) -> PluginRTCPeerConnection? {
        let pluginRTCPeerConnection = self.pluginRTCPeerConnections[pcId]
        
        if pluginRTCPeerConnection == nil {
            print("iosrtcPlugin - getRTCPeerConnection() | ERROR: pluginRTCPeerConnection with pcId= \(pcId) does not exist")
        }
        return pluginRTCPeerConnection
    }
    
    func getMediaStream(streamId:String) -> PluginMediaStream? {
        let pluginMediaStream = self.pluginMediaStreams[streamId]
        
        if pluginMediaStream == nil {
            print("iosrtcPlugin - getMediaStream() | ERROR: pluginMediaStream with id=\(streamId) does not exist")
        }
        return pluginMediaStream
    }
    
    func removeRTCPeerConnection(pcId:Int) {
        // Remove the pluginRTCPeerConnection from the dictionary.
        self.pluginRTCPeerConnections[pcId] = nil
    }
    
    
    func setChannelListener(pcId:Int, dcId:Int, onData: (data: NSDictionary) -> Void, onBinaryMessage: (data: NSData) -> Void) {
        dispatchWithConnection(pcId) { connection in
            connection.RTCDataChannel_setListener(dcId,
                                                  eventListener: onData,
                                                  eventListenerForBinaryMessage: onBinaryMessage
            )
        }
    }
    
    func dispatchWithConnection(pcId:Int, handler: (connection: PluginRTCPeerConnection) -> Void) {
        if let connection = getRTCPeerConnection(pcId) {
            dispatch_async(self.queue) {
                handler(connection: connection)
            }
        }
    }
    
    
    func dispatchWithConnectionAndMediaStream(pcId:Int, streamId:String, handler: (connection: PluginRTCPeerConnection, mediaStream: PluginMediaStream) -> Void) {
        if let connection = getRTCPeerConnection(pcId) {
            if let mediaStream = getMediaStream(streamId) {
                dispatch_async(self.queue) {
                    handler(connection: connection, mediaStream: mediaStream)
                }
            }
        }
    }
    
    func dispatchWithMediaStream(streamId:String, handler: (mediaStream: PluginMediaStream) -> Void) {
        if let mediaStream = getMediaStream(streamId) {
            dispatch_async(self.queue) {
                handler(mediaStream: mediaStream)
            }
        }
    }
    
    func setMediaStreamListener(streamId:String, onData: (data: NSDictionary) -> Void) {
        dispatchWithMediaStream(streamId) { mediaStream in
            mediaStream.setListener(onData, eventListenerForAddTrack: self.saveMediaStreamTrack, eventListenerForRemoveTrack: self.deleteMediaStreamTrack)
        }
    }
    
    func setMediaStreamTrackListener(trackId:String, listener: (data: NSDictionary) -> Void) {
        if let track = getMediaStreamTrack(trackId) {
            dispatch_async(self.queue) {
                track.setListener(listener) { () -> Void in
                    // Remove the track from the container.
                    self.pluginMediaStreamTracks[track.id] = nil
                }
            }
        }
    }
    
    func getUserMedia(constraints:NSDictionary, onData: (data: NSDictionary) -> Void, onError: (error:NSError) -> Void) {
        self.pluginGetUserMedia.call(constraints,
                                     callback: onData,
                                     errback: { (error: String) -> Void in
                                        onError(error: NSError(domain: "iosrtcPlugin", code: 10011, userInfo: [NSLocalizedDescriptionKey:error, NSLocalizedFailureReasonErrorKey:error]))
                                     },
                                     eventListenerForNewStream: self.saveMediaStream
        )
    }
    
    func setMediaStreamTrackEnabled(trackId:String, value:Bool) {
        if let track = getMediaStreamTrack(trackId) {
            dispatch_async(self.queue) {
                track.setEnabled(value)
            }
        }
    }
    
    func stopMediaStreamTrack(trackId:String) {
        if let track = getMediaStreamTrack(trackId) {
            dispatch_async(self.queue) {
                track.stop()
            }
        }
    }
    
    func newMediaStreamRenderer(id:Int, webView:UIWebView, eventListener:(data: NSDictionary) -> Void) {
        let streamRenderer = PluginMediaStreamRenderer(
            webView: webView,
            eventListener:eventListener
        )
        
        self.pluginMediaStreamRenderers[id] = streamRenderer
        
        streamRenderer.run()
    }
    
    func getStreamRenderer(id:Int) -> PluginMediaStreamRenderer? {
        if let streamRenderer = self.pluginMediaStreamRenderers[id] {
            return streamRenderer
        }
        print ("iosrtcPlugin - getStreamRenderer() | ERROR: pluginMediaStreamRenderer with id=\(id) does not exist")
        return nil
    }
    
    func renderOnMediaRenderer(id:Int, streamId:String) {
        if let mediaStream = getMediaStream(streamId) {
            if let streamRenderer = getStreamRenderer(id) {
                streamRenderer.render(mediaStream)
            }
        }
    }
    
    func mediaStreamChanged(id:Int) {
        if let streamRenderer = getStreamRenderer(id) {
            streamRenderer.mediaStreamChanged()
        }
    }
    
    func closeMediaStreamRenderer(id:Int) {
        if let streamRenderer = getStreamRenderer(id) {
            streamRenderer.close()
            self.pluginMediaStreamRenderers[id] = nil
        }
    }
    
    
    
    func refreshMediaStreamRenderer(id:Int, data:NSDictionary) {
        if let streamRenderer = getStreamRenderer(id) {
            streamRenderer.refresh(data)
        }
    }
    
    func getMediaStreamTrack(trackId:String) -> PluginMediaStreamTrack? {
        if let track = pluginMediaStreamTracks[trackId] {
            return track
        }
        print ("iosrtcPlugin - getMediaStreamTrack() | ERROR: pluginMediaStreamTrack with id=\(trackId) does not exist")
        return nil
    }
    
    func addTrackToMediaStream(streamId:String, trackId:String) {
        if let track = getMediaStreamTrack(trackId) {
            dispatchWithMediaStream(streamId) { mediaStream in
                mediaStream.addTrack(track)
            }
        }
    }
    
    func removeTrackFromMediaStream(streamId:String, trackId:String) {
        if let track = getMediaStreamTrack(trackId) {
            dispatchWithMediaStream(streamId) { mediaStream in
                mediaStream.removeTrack(track)
            }
        }
    }

    func releaseMediaStream(streamId:String) {
        if getMediaStream(streamId) != nil {
            self.pluginMediaStreams[streamId] = nil
        }
    }
    
    func sendStringOnChannel(pcId:Int, dcId:Int, data:String, onData: (data: NSDictionary) -> Void) {
        dispatchWithConnection(pcId) { connection in
            connection.RTCDataChannel_sendString(dcId,
                                                 data: data,
                                                 callback: onData
            )
        }
    }
    
    func sendBinaryOnChannel(pcId:Int, dcId:Int, data:NSData, onData: (data: NSDictionary) -> Void) {
        dispatchWithConnection(pcId) { connection in
            connection.RTCDataChannel_sendBinary(dcId,
                                                 data: data,
                                                 callback: onData
            )
        }
    }
    
    func closeDataChannel(pcId:Int, dcId: Int) {
        dispatchWithConnection(pcId) { connection in
            connection.RTCDataChannel_close(dcId)
        }
    }
    
    func closeConnection(pcId:Int) {
        dispatchWithConnection(pcId) { connection in
            connection.close()
            self.removeRTCPeerConnection(pcId)
        }
    }
    
    
    func dump(command: CDVInvokedUrlCommand) {
        print("iosrtcPlugin#dump()")
        
        for (id, _) in self.pluginRTCPeerConnections {
            print("- PluginRTCPeerConnection [id:\(id)]")
        }
        
        for (_, pluginMediaStream) in self.pluginMediaStreams {
            print("- PluginMediaStream \(pluginMediaStream.rtcMediaStream.description)")
        }
        
        for (id, pluginMediaStreamTrack) in self.pluginMediaStreamTracks {
            print("- PluginMediaStreamTrack [id: \(id), kind: \(pluginMediaStreamTrack.kind)]")
        }
        
        for (id, _) in self.pluginMediaStreamRenderers {
            print("- PluginMediaStreamRenderer [id:\(id)")
        }
    }
    
    private func saveMediaStream(pluginMediaStream: PluginMediaStream) {
        if self.pluginMediaStreams[pluginMediaStream.id] == nil {
            self.pluginMediaStreams[pluginMediaStream.id] = pluginMediaStream
        } else {
            return;
        }
        
        // Store its PluginMediaStreamTracks' into the dictionary.
        for (id, track) in pluginMediaStream.audioTracks {
            if self.pluginMediaStreamTracks[id] == nil {
                self.pluginMediaStreamTracks[id] = track
            }
        }
        for (id, track) in pluginMediaStream.videoTracks {
            if self.pluginMediaStreamTracks[id] == nil {
                self.pluginMediaStreamTracks[id] = track
            }
        }
    }
    
    private func deleteMediaStream(id: String) {
        self.pluginMediaStreams[id] = nil
    }
    
    private func saveMediaStreamTrack(pluginMediaStreamTrack: PluginMediaStreamTrack) {
        if self.pluginMediaStreamTracks[pluginMediaStreamTrack.id] == nil {
            self.pluginMediaStreamTracks[pluginMediaStreamTrack.id] = pluginMediaStreamTrack
        }
    }
    
    
    private func deleteMediaStreamTrack(id: String) {
        self.pluginMediaStreamTracks[id] = nil
    }
}

@objc(iosrtcPlugin) // This class must be accesible from Objective-C.
class iosrtcPlugin : CDVPlugin {
	
    var listOfMediaStreamRenderers:[Int] = []
    
    override func pluginInitialize() {
		print("iosrtcPlugin#pluginInitialize() | doing nothing")
        
	}


	override func onReset() {
		print("iosrtcPlugin#onReset() | doing nothing")
	}

    override func dispose() {
        for id in self.listOfMediaStreamRenderers {
            iosrtcPluginSingleton.sharedInstance.closeMediaStreamRenderer(id)
        }
    }

	override func onAppTerminate() {
		print("iosrtcPlugin#onAppTerminate() | doing nothing")
	}
    
    private func emit(callbackId: String, result: CDVPluginResult) {
        dispatch_async(dispatch_get_main_queue()) {
            if let delegate = self.commandDelegate {
                delegate.sendPluginResult(result, callbackId: callbackId)
            }
            else{
                print("WARN: No delegate available !!!");
            }
        }
    }
    
    /**
     This function return a common eventHandler with logging and keepCallback options.
    */
    private func emitDataAsDictionary(callbackId:String, keepCallBack: Bool = false, nameForLogging:String = "Not Defined") -> ((NSDictionary) -> Void ) {
        return { (data) in
            let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAsDictionary: data as [NSObject : AnyObject])
            
            if(nameForLogging != "Not Defined") {
                print("iosrtcPlugin -> [\(nameForLogging)] - emitDataAsDictionary -> data(as dictionary) : \(data.description) ")
            }
            
            if(keepCallBack){
                result.setKeepCallbackAsBool(keepCallBack)
            }
            
            self.emit(callbackId, result: result)
        };
    }
    
    private func emitDataAsBinary(callbackId:String, keepCallBack: Bool = false, nameForLogging:String = "Not Defined") -> ((NSData) -> Void ) {
        return { (data) in
            let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAsArrayBuffer: data)
        
            if(nameForLogging != "Not Defined") {
                print("iosrtcPlugin -> [\(nameForLogging)] - emitDataAsDictionary -> data(as dictionary) : \(data.description) ")
            }
            
            if(keepCallBack){
                result.setKeepCallbackAsBool(keepCallBack)
            }
            
            self.emit(callbackId, result: result)
        }
    }
    
    private func logCommand(nameForLogging:String, command: CDVInvokedUrlCommand) {
        print("command - [\(nameForLogging)] \n methodName: \(command.methodName) \n arguments: \(command.arguments.description) ");
    }
    
    
    private func emitError(callbackId:String, nameForLogging:String = "Unknown") -> ((NSError) -> Void ) {
        return { (error:NSError) in
            
            print("iosrtcPlugin -> [\(nameForLogging)] - emitError: \(error.localizedDescription) - \n description: \(error.description) \n debugDescription: \(error.debugDescription) ")
            
            self.emit(callbackId, result: CDVPluginResult(status: CDVCommandStatus_ERROR, messageAsString: error.localizedDescription)
            )
        }
    }


	func new_RTCPeerConnection(command: CDVInvokedUrlCommand) {
        
        logCommand("new_RTCPeerConnection", command: command);
        
		let pcId = command.argumentAtIndex(0) as! Int
		var pcConfig: NSDictionary?
		var pcConstraints: NSDictionary?

		if command.argumentAtIndex(1) != nil {
			pcConfig = command.argumentAtIndex(1) as? NSDictionary
		}

		if command.argumentAtIndex(2) != nil {
			pcConstraints = command.argumentAtIndex(2) as? NSDictionary
		}

        iosrtcPluginSingleton.sharedInstance.newConnection(pcId, pcConfig: pcConfig, pcConstraints: pcConstraints, eventListener: emitDataAsDictionary(command.callbackId, keepCallBack: true) )
	}


	func RTCPeerConnection_createOffer(command: CDVInvokedUrlCommand) {
        logCommand("RTCPeerConnection_createOffer", command: command);

		let pcId = command.argumentAtIndex(0) as! Int
		var options: NSDictionary?

		if command.argumentAtIndex(1) != nil {
			options = command.argumentAtIndex(1) as? NSDictionary
		}
        
        iosrtcPluginSingleton.sharedInstance.createOffer(pcId, options: options, onData: emitDataAsDictionary(command.callbackId), onError: emitError(command.callbackId))
    }


	func RTCPeerConnection_createAnswer(command: CDVInvokedUrlCommand) {
        logCommand("RTCPeerConnection_createAnswer", command: command);

		let pcId = command.argumentAtIndex(0) as! Int
		var options: NSDictionary?

		if command.argumentAtIndex(1) != nil {
			options = command.argumentAtIndex(1) as? NSDictionary
		}
        
        iosrtcPluginSingleton.sharedInstance.createAnswer(pcId, options: options, onData:emitDataAsDictionary(command.callbackId), onError: emitError(command.callbackId))
	}

	func RTCPeerConnection_setLocalDescription(command: CDVInvokedUrlCommand) {
        logCommand("RTCPeerConnection_setLocalDescription", command: command);

		let pcId = command.argumentAtIndex(0) as! Int
		let desc = command.argumentAtIndex(1) as! NSDictionary
        
        iosrtcPluginSingleton.sharedInstance.setLocalDescription(pcId, desc: desc, onData:emitDataAsDictionary(command.callbackId), onError: emitError(command.callbackId))
	}


	func RTCPeerConnection_setRemoteDescription(command: CDVInvokedUrlCommand) {
		logCommand("RTCPeerConnection_setRemoteDescription", command: command);

		let pcId = command.argumentAtIndex(0) as! Int
		let desc = command.argumentAtIndex(1) as! NSDictionary
        
        iosrtcPluginSingleton.sharedInstance.setRemoteDescription(pcId, desc: desc, onData:emitDataAsDictionary(command.callbackId), onError: emitError(command.callbackId))
	}


	func RTCPeerConnection_addIceCandidate(command: CDVInvokedUrlCommand) {
        logCommand("RTCPeerConnection_addIceCandidate", command: command);
        
		let pcId = command.argumentAtIndex(0) as! Int
		let candidate = command.argumentAtIndex(1) as! NSDictionary
    
        iosrtcPluginSingleton.sharedInstance.addIceCandidate(pcId, candidate: candidate, onData:emitDataAsDictionary(command.callbackId), onError: emitError(command.callbackId))
	}


	func RTCPeerConnection_addStream(command: CDVInvokedUrlCommand) {
		logCommand("RTCPeerConnection_addStream", command: command);

		let pcId = command.argumentAtIndex(0) as! Int
		let streamId = command.argumentAtIndex(1) as! String
        
        iosrtcPluginSingleton.sharedInstance.addStream(pcId, streamId: streamId);
	}


	func RTCPeerConnection_removeStream(command: CDVInvokedUrlCommand) {
		logCommand("RTCPeerConnection_removeStream", command: command);

		let pcId = command.argumentAtIndex(0) as! Int
		let streamId = command.argumentAtIndex(1) as! String
        
        iosrtcPluginSingleton.sharedInstance.removeStream(pcId, streamId: streamId);
	}


	func RTCPeerConnection_createDataChannel(command: CDVInvokedUrlCommand) {
		logCommand("RTCPeerConnection_createDataChannel", command: command)

		let pcId = command.argumentAtIndex(0) as! Int
		let dcId = command.argumentAtIndex(1) as! Int
		let label = command.argumentAtIndex(2) as! String
		var options: NSDictionary?

		if command.argumentAtIndex(3) != nil {
			options = command.argumentAtIndex(3) as? NSDictionary
		}
        
        iosrtcPluginSingleton.sharedInstance.createDataChannel(pcId, dcId: dcId, label: label, options: options!,
                                                               onData: emitDataAsDictionary(command.callbackId, keepCallBack: true, nameForLogging: "RTCPeerConnection_createDataChannel"),
                                                               onBinaryMessage: emitDataAsBinary(command.callbackId, keepCallBack: true, nameForLogging: "RTCPeerConnection_createDataChannel"))
        
	}


	func RTCPeerConnection_close(command: CDVInvokedUrlCommand) {
		logCommand("RTCPeerConnection_close", command: command)

		let pcId = command.argumentAtIndex(0) as! Int
        
        iosrtcPluginSingleton.sharedInstance.closeConnection(pcId)
	}


	func RTCPeerConnection_RTCDataChannel_setListener(command: CDVInvokedUrlCommand) {
        let nameForLogging = "RTCPeerConnection_RTCDataChannel_setListener"
		logCommand(nameForLogging, command: command)

		let pcId = command.argumentAtIndex(0) as! Int
		let dcId = command.argumentAtIndex(1) as! Int
        
        iosrtcPluginSingleton.sharedInstance.setChannelListener(pcId, dcId: dcId,
                                                                onData: emitDataAsDictionary(command.callbackId, keepCallBack: true, nameForLogging: nameForLogging),
                                                                onBinaryMessage: emitDataAsBinary(command.callbackId, keepCallBack: true, nameForLogging: nameForLogging))
	}


	func RTCPeerConnection_RTCDataChannel_sendString(command: CDVInvokedUrlCommand) {
        let nameForLogging = "RTCPeerConnection_RTCDataChannel_sendString"
        logCommand(nameForLogging, command: command)

		let pcId = command.argumentAtIndex(0) as! Int
		let dcId = command.argumentAtIndex(1) as! Int
		let data = command.argumentAtIndex(2) as! String
        
        
        iosrtcPluginSingleton.sharedInstance.sendStringOnChannel(pcId, dcId: dcId, data:data,
                                                                onData: emitDataAsDictionary(command.callbackId, nameForLogging: nameForLogging))
	}


	func RTCPeerConnection_RTCDataChannel_sendBinary(command: CDVInvokedUrlCommand) {
        let nameForLogging = "RTCPeerConnection_RTCDataChannel_sendBinary"
        logCommand(nameForLogging, command: command)

		let pcId = command.argumentAtIndex(0) as! Int
		let dcId = command.argumentAtIndex(1) as! Int
		let data = command.argumentAtIndex(2) as! NSData
        
        iosrtcPluginSingleton.sharedInstance.sendBinaryOnChannel(pcId, dcId: dcId, data:data,
                                                                 onData: emitDataAsDictionary(command.callbackId, nameForLogging: nameForLogging))
	}


	func RTCPeerConnection_RTCDataChannel_close(command: CDVInvokedUrlCommand) {
        let nameForLogging = "RTCPeerConnection_RTCDataChannel_close"
        logCommand(nameForLogging, command: command)
        
        let pcId = command.argumentAtIndex(0) as! Int
		let dcId = command.argumentAtIndex(1) as! Int
        
        iosrtcPluginSingleton.sharedInstance.closeDataChannel(pcId, dcId: dcId)
	}


	func MediaStream_setListener(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStream_setListener"
        logCommand(nameForLogging, command: command)

		let id = command.argumentAtIndex(0) as! String
        
        iosrtcPluginSingleton.sharedInstance.setMediaStreamListener(id,onData: emitDataAsDictionary(command.callbackId, keepCallBack: true, nameForLogging: nameForLogging))
	}


	func MediaStream_addTrack(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStream_addTrack"
        logCommand(nameForLogging, command: command)
        
        let id = command.argumentAtIndex(0) as! String
		let trackId = command.argumentAtIndex(1) as! String
        
        iosrtcPluginSingleton.sharedInstance.addTrackToMediaStream(id, trackId:trackId)
    }


	func MediaStream_removeTrack(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStream_removeTrack"
        logCommand(nameForLogging, command: command)
        
        let id = command.argumentAtIndex(0) as! String
		let trackId = command.argumentAtIndex(1) as! String
        
        iosrtcPluginSingleton.sharedInstance.removeTrackFromMediaStream(id, trackId:trackId)
	}


	func MediaStream_release(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStream_release"
        logCommand(nameForLogging, command: command)
        
        let id = command.argumentAtIndex(0) as! String
        
        iosrtcPluginSingleton.sharedInstance.releaseMediaStream(id)
    }

	func MediaStreamTrack_setListener(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStreamTrack_setListener"
        logCommand(nameForLogging, command: command)
        
        let trackId = command.argumentAtIndex(0) as! String
        
        iosrtcPluginSingleton.sharedInstance.setMediaStreamTrackListener(
            trackId,
            listener:emitDataAsDictionary(command.callbackId, keepCallBack: true, nameForLogging: nameForLogging)
        )
	}

	func MediaStreamTrack_setEnabled(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStreamTrack_setEnabled"
        logCommand(nameForLogging, command: command)
        
        let trackId = command.argumentAtIndex(0) as! String
        let value = command.argumentAtIndex(1) as! Bool
        
        iosrtcPluginSingleton.sharedInstance.setMediaStreamTrackEnabled(trackId, value:value)
	}

	func MediaStreamTrack_stop(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStreamTrack_stop"
        logCommand(nameForLogging, command: command)
        
        let trackId = command.argumentAtIndex(0) as! String
        
        iosrtcPluginSingleton.sharedInstance.stopMediaStreamTrack(trackId)
	}

	func new_MediaStreamRenderer(command: CDVInvokedUrlCommand) {
        let nameForLogging = "new_MediaStreamRenderer"
        logCommand(nameForLogging, command: command)
        
        let id = command.argumentAtIndex(0) as! Int
        
        self.listOfMediaStreamRenderers.append(id)

        iosrtcPluginSingleton.sharedInstance.newMediaStreamRenderer(
            id,
            webView:self.webView!,
            eventListener: emitDataAsDictionary(command.callbackId, keepCallBack: true, nameForLogging: nameForLogging))
	}

	func MediaStreamRenderer_render(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStreamRenderer_render"
        logCommand(nameForLogging, command: command)
        
        let id = command.argumentAtIndex(0) as! Int
        let streamId = command.argumentAtIndex(1) as! String
        
        iosrtcPluginSingleton.sharedInstance.renderOnMediaRenderer(id, streamId:streamId)
	}

	func MediaStreamRenderer_mediaStreamChanged(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStreamRenderer_mediaStreamChanged"
        logCommand(nameForLogging, command: command)
        
        let id = command.argumentAtIndex(0) as! Int
        
        iosrtcPluginSingleton.sharedInstance.mediaStreamChanged(id)
	}

	func MediaStreamRenderer_refresh(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStreamRenderer_refresh"
        logCommand(nameForLogging, command: command)
        
        let id = command.argumentAtIndex(0) as! Int
		let data = command.argumentAtIndex(1) as! NSDictionary
        
        iosrtcPluginSingleton.sharedInstance.refreshMediaStreamRenderer(id, data:data)
	}


	func MediaStreamRenderer_close(command: CDVInvokedUrlCommand) {
        let nameForLogging = "MediaStreamRenderer_close"
        logCommand(nameForLogging, command: command)
        
        let id = command.argumentAtIndex(0) as! Int
        
        iosrtcPluginSingleton.sharedInstance.closeMediaStreamRenderer(id)
	}


	func getUserMedia(command: CDVInvokedUrlCommand) {
        let nameForLogging = "getUserMedia"
        logCommand(nameForLogging, command: command)
        
        let constraints = command.argumentAtIndex(0) as! NSDictionary
        
        iosrtcPluginSingleton.sharedInstance.getUserMedia(
            constraints,
            onData: emitDataAsDictionary(command.callbackId, nameForLogging: nameForLogging),
            onError: emitError(command.callbackId))
	}


	func enumerateDevices(command: CDVInvokedUrlCommand) {
        let nameForLogging = "enumerateDevices"
        logCommand(nameForLogging, command: command)
        
        PluginEnumerateDevices.call(emitDataAsDictionary(command.callbackId, nameForLogging: nameForLogging))
	}


	func selectAudioOutputEarpiece(command: CDVInvokedUrlCommand) {
        let nameForLogging = "selectAudioOutputEarpiece"
        logCommand(nameForLogging, command: command)
        
        do {
			try AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSessionPortOverride.None)
		} catch {
			NSLog("iosrtcPlugin#selectAudioOutputEarpiece() | ERROR: %@", String(error))
		};
	}


	func selectAudioOutputSpeaker(command: CDVInvokedUrlCommand) {
        let nameForLogging = "selectAudioOutputSpeaker"
        logCommand(nameForLogging, command: command)
        
        do {
			try AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSessionPortOverride.Speaker)
		} catch {
			NSLog("iosrtcPlugin#selectAudioOutputSpeaker() | ERROR: %@", String(error))
		};
	}
}
