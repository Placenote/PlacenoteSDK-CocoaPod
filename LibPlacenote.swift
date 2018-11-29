//
//  LibPlacenote.swift
//  PlacenoteSDK
//
//  Created by Yan Ma on 2017-12-27.
//  Copyright © 2017 Vertical AI. All rights reserved.
//

import Foundation
import SceneKit
import GLKit
import os.log

/// Untility functions to matrix_float4x4
extension matrix_float4x4 {
  /**
   Calculate position vector of a pose matrix
   
   - Returns: A SCNVector3 from the translation components of the matrix
   */
  public func position() -> SCNVector3 {
    return SCNVector3(columns.3.x, columns.3.y, columns.3.z)
  }
  
  /**
   Calculate a quaternion of a pose matrix
   
   - Returns: A SCNVector3 from the translation components of the matrix
   */
  func rotation() -> SCNQuaternion {
    let quat: simd_quatf = simd_quaternion(self)
    return SCNQuaternion(quat.imag.x, quat.imag.y, quat.imag.z, quat.real)
  }
  
  /**
   Describe the content of the matrix in a string
   
   - Returns: A string that contains the content of the matrix
   */
  func describe() -> String {
    let description: String = String(
      format: "%f %f %f %f\n%f %f %f %f\n %f %f %f %f\n %f %f %f %f\n",
      columns.0.x, columns.1.x, columns.2.x, columns.3.x,
      columns.0.y, columns.1.y, columns.2.y, columns.3.y,
      columns.0.z, columns.1.z, columns.2.z, columns.3.z,
      columns.0.w, columns.1.w, columns.2.w, columns.3.w
    )
    return description
  }
  
  /**
   Convert a PNTransform to a matrix_float4x4
   
   - Returns: a matrix_float4x4 that corresponds to the 'pose' transform
   */
  static func fromPNTransform(pose: PNTransform) -> matrix_float4x4 {
    let quat: simd_quatf = simd_quatf(ix: pose.rotation.x, iy: pose.rotation.y, iz: pose.rotation.z, r: pose.rotation.w)
    var matrix: simd_float4x4 = simd_float4x4.init(quat)
    matrix.columns.3.x = pose.position.x
    matrix.columns.3.y = pose.position.y
    matrix.columns.3.z = pose.position.z
    return matrix
  }
}

extension SCNMatrix4 {
  /**
   Describe the content of the matrix in a string
   
   - Returns: A string that contains the content of the matrix
   */
  func describe() -> String {
    let description: String = String(format: "%f %f %f %f\n%f %f %f %f\n %f %f %f %f\n %f %f %f %f",
        m11, m21, m31, m41, m12, m22, m32, m42, m13, m23, m33, m43, m14, m24, m34, m44, m41, m42, m43)
    return description
  }
}

extension Date {
  /**
   Return the total milliseconds since epoch
   
   - Returns: An int that contains the total milliseconds since epoch
   */
  var millisecondsSince1970:Int {
    return Int((self.timeIntervalSince1970 * 1000.0).rounded())
  }
}



/// Interface to be implemented by listener classes that subscribes to pose and mapping status from LibPlacenote
public protocol PNDelegate {
  /**
   Callback to subscribe to pose measurements from LibPlacenote
   
   - Parameter outputPose: Inertial pose with respect to the map LibPlacenote is tracking against.
   - Parameter arkitPose: Odometry pose with respect to the ARKit coordinate frame that corresponds with 'outputPose' in time.
   */
  func onPose(_ outputPose: matrix_float4x4, _ arkitPose: matrix_float4x4) -> Void
  
  /**
   Callback to subscribe to mapping session status changes.
   
   - Parameter prevStatus: Status before the status change
   - Parameter currStatus: Current status of the mapping engine
   */
  func onStatusChange(_ prevStatus: LibPlacenote.MappingStatus, _ currStatus: LibPlacenote.MappingStatus) -> Void
}


/// Swift wrapper of LibPlacenote C API
public class LibPlacenote {
  public typealias PoseCallback = (_ outputPose: matrix_float4x4, _ arkitPose: matrix_float4x4)-> Void
  public typealias SaveMapCallback = (_ mapId: String?) -> Void
  public typealias FileTransferCallback = (_ completed: Bool, _ faulted: Bool, _ percentage: Float) -> Void
  public typealias DeleteMapCallback = (_ deleted: Bool) -> Void
  public typealias MetadataSavedCallback = (_ success: Bool) -> Void
  public typealias GetMetadataCallback = (_ success: Bool, _ metadata: MapMetadata) -> Void
  public typealias ListMapCallback = (_ success: Bool, _ mapList: [String: MapMetadata]) -> Void
  public typealias OnInitializedCallback = (_ success: Bool) -> Void

  
  /// Enums that indicates the status of the LibPlacenote mapping module
  public enum MappingStatus {
    /// Indicates that the mapping module is waiting for request to start a mapping session.
    /// When 'stopSession' is called, the status will be reset to 'waiting'
    case waiting
    /// Indicates that a mapping/localization session is currently running and returning poses
    case running
    /// Indicates that the localization module module currently fails to find a valid pose
    /// within the given map, and will keep trying.
    case lost
  }
  
  /// A helper class that contains the context information about a callback that gets passed between the C and Swift runtimes
  private class CallbackContext {
    var callbackId: Int
    var libPtr: LibPlacenote
    
    init(id: String, ptr: LibPlacenote) {
      callbackId = id.hash
      libPtr = ptr
    }
  }

  /// Struct that contains location data for the map. All fields are required.
  public class MapLocation: Codable
  {
    public init() {}

    /// The GPS latitude
    public var latitude: Double = 0
    /// The GPS longitude
    public var longitude: Double = 0
    /// The GPS altitude
    public var altitude: Double = 0
  }
  
  /// Structure used for searching your maps. All fields are optional.
  /// When multiple fields are set the search condition is logically ANDed,
  /// returning a smaller list of maps.
  public class MapSearch: Codable
  {
    /// The map name to search for. The search is case insensitive and will match
    /// and map that's name included the search name.
    public var name: String? = nil
    /// The location to search for maps in. Maps without location data will
    /// not be returned if this is set.
    public var location: MapLocationSearch?;
    /// Only return maps newer than this (in milliseconds since EPOCH). Value '0' disable this constraint.
    public var newerThan: Double = 0;
    /// Only return maps older than this (in milliseconds since EPOCH). Value '0' disable this constraint.
    public var olderThan: Double = 0;
    /// Filter maps based on this query, which is run via json-query:
    /// https://www.npmjs.com/package/json-query
    /// The filter will match if the query return a valid.
    ///
    /// For a simple example, to match only maps that have a 'shapeList'
    /// in the userdata object, simply pass 'shapeList'.
    ///
    /// For other help, contact us on Slack.
    public var userdataQuery: String? = nil
    
    /// <summary>
    /// Helper function for setting newerThan via a DateTime
    /// </summary>
    public func setNewerThan(dt: Date) -> Void {
      newerThan = Double(dt.millisecondsSince1970);
    }
    
    /// <summary>
    /// Helper function for setting olderThan via a DateTime
    /// </summary>
    public func setOlderThan(dt: Date)  -> Void {
      olderThan = Double(dt.millisecondsSince1970);
    }
  }

  /// Struct for searching maps by location. All fields are required.
  public class MapLocationSearch: Codable
  {
    public init() {}

    /// The GPS latitude for the center of the search circle.
    public var latitude: Double = 0
    /// The GPS longitude for the center of the search circle.
    public var longitude: Double = 0
    /// The radius (in meters) of the search circle.
    public var radius: Double = 0
  }

  /// Struct for setting map metadata. All fields are optional.
  public class MapMetadataSettable
  {
    public init() {}

    /// The map name.
    public var name: String? = nil

    /// The map location information.
    public var location: MapLocation? = nil

    /// Arbitrary user data, in JSON form.
    public var userdata: Any? = nil
  }

  /// <summary>
  /// Struct for getting map metatada.
  /// </summary>
  public class MapMetadata : MapMetadataSettable
  {
    /// The creation time of the map (in milliseconds since EPOCH).
    public var created: UInt64? = nil
  }
  
  /// Static instance of the LibPlacenote singleton
  private static var _instance = LibPlacenote()
  public static var instance: LibPlacenote {
    get {
        return _instance
    }
  }
  
  /// A multicast delegate developers can append to in order to subscribe
  /// to the pose and status events from LibPlacenote
  public var multiDelegate: MulticastPNDelegate = MulticastPNDelegate()
  
  private typealias NativeInitResultPtr = UnsafeMutablePointer<PNCallbackResult>
  private typealias NativePosePtr = UnsafeMutablePointer<PNTransform>
  private var currTransform: matrix_float4x4 = matrix_identity_float4x4
  
  private var sdkInitialized: Bool = false
  private let mapStoragePath: String = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
  
  private var mapList: [String: Any] = [:]
  private var mapTransferCbDict: Dictionary<Int, FileTransferCallback> = Dictionary()
  private var saveMapCbDict: Dictionary<Int, SaveMapCallback> = Dictionary()
  private var deleteMapCbDict: Dictionary<Int, DeleteMapCallback> = Dictionary()
  private var listMapCbDict: Dictionary<Int, ListMapCallback> = Dictionary()
  private var setMetadataCbDict: Dictionary<Int, MetadataSavedCallback> = Dictionary()
  private var getMetadataCbDict: Dictionary<Int, GetMetadataCallback> = Dictionary()
  private var onInitializedCbDict: Dictionary<Int, OnInitializedCallback> = Dictionary()
  private var ctxDict: Dictionary<Int, CallbackContext> = Dictionary()
  private var prevStatus: MappingStatus = MappingStatus.waiting
  private var currStatus: MappingStatus = MappingStatus.waiting
  
  /**
   Function to initialize the LibPlacenote SDK, must be called before any other function is invoked
   */
  public func initialize(apiKey: String, onInitialized: (OnInitializedCallback)? = nil) -> Void {
    let cbCtx: CallbackContext = CallbackContext(id: UUID().uuidString, ptr: self)
    onInitializedCbDict[cbCtx.callbackId] = onInitialized;
    ctxDict[cbCtx.callbackId] = cbCtx
    let anUnmanaged = Unmanaged<CallbackContext>.passUnretained(ctxDict[cbCtx.callbackId]!)
    let ctxPtr = UnsafeMutableRawPointer(anUnmanaged.toOpaque())
    
    os_log ("initializing SDK")

    let manager = FileManager.default

    var dataPath = Bundle.main.bundlePath
    if (!manager.fileExists(atPath: dataPath + "/Data.bin")) {
        dataPath = Bundle.main.bundlePath + "/Frameworks/PlacenoteSDK.framework"
        if (!manager.fileExists(atPath: dataPath + "/Data.bin")) {
            os_log ("Failed to locate Data.bin!")
            return
        }
    }

    initializeSDK(apiKey, mapStoragePath, dataPath, ctxPtr, {(result: NativeInitResultPtr?, ctxPtr: UnsafeMutableRawPointer?) -> Void in
      let success = result?.pointee.success
      let cbReturnedCtx = Unmanaged<CallbackContext>.fromOpaque(ctxPtr!).takeUnretainedValue()
      let callbackId = cbReturnedCtx.callbackId
      let libPtr = cbReturnedCtx.libPtr
    
      if (result != nil && success!) {
        os_log("Initialized SDK!")
        libPtr.sdkInitialized = true;
        let cb = libPtr.onInitializedCbDict[callbackId]
        if (cb != nil) {
          cb!(true);
        }
      } else {
        os_log("Failed to initialize SDK!", log: OSLog.default, type: .error)
        let errMsg = result?.pointee.msg
        var str: String = ""
        if (result != nil) {
          str = String(cString: errMsg!, encoding: String.Encoding.ascii)!
          os_log ("Error: %@", log: OSLog.default, type: .error, str)
        }
        let cb = libPtr.onInitializedCbDict[callbackId]
        if (cb != nil) {
          cb!(false);
        }
      }
    })
  }
  
  /**
   Accessor function that returns initialization status of LibPlacenote
   
   - Returns: A Bool that indicates whether LibPlacenote SDK is initialized
   */
  public func initialized() -> Bool {
    return sdkInitialized
  }
  
  /**
   Function to shutdown all LibPlacenote SDK functions, creates a cleaner exit and shutdown of critical mapper threads
   */
  public func shutdown() -> Void {
    PNShutdown()
  }
  
  /**
   Function to start a mapping/localization session in LibPlacenote.
   If a map is loaded before startSession is called, libPlacenote will
   localize against the loaded map without mapping. If not, it will start
   mapping the environment.
   
   - Returns: A Bool that indicates whether LibPlacenote SDK is initialized
   */
  public func startSession(extend: Bool = false) -> Void {
    let anUnmanaged = Unmanaged<LibPlacenote>.passUnretained(self)
    let ctxPtr = UnsafeMutableRawPointer(anUnmanaged.toOpaque())
    PNStartSession({(outputPose: NativePosePtr?, arkitPose: NativePosePtr?, swiftContext: UnsafeMutableRawPointer?) -> Void in
      if (outputPose == nil) {
        os_log("outputPose null",log: OSLog.default, type: .error)
        return
      }
      
      if (arkitPose == nil) {
        os_log("arkitPose null",log: OSLog.default, type: .error)
        return
      }
      
      if (swiftContext != nil) {
        let libPtr = Unmanaged<LibPlacenote>.fromOpaque(swiftContext!).takeUnretainedValue()
        let outputMat:matrix_float4x4 = matrix_float4x4.fromPNTransform(pose: (outputPose?.pointee)!)
        let arkitMat:matrix_float4x4 = matrix_float4x4.fromPNTransform(pose: (arkitPose?.pointee)!)
        
        DispatchQueue.main.async(execute: {() -> Void in
          let status = libPtr.getMappingStatus()
          if (status == LibPlacenote.MappingStatus.running) {
            libPtr.multiDelegate.onPose(outputPose: outputMat, arkitPose: arkitMat)
            libPtr.currTransform = outputMat*arkitMat.inverse
          }
          
          if (status != libPtr.prevStatus) {
            libPtr.multiDelegate.onStatusChange(prevStatus: libPtr.prevStatus, currStatus: status)
            libPtr.prevStatus = status
          }
          libPtr.currStatus = status
        })
      }
    }, extend, ctxPtr)
  }
  
  /**
   Function to start a mapping/localization session in LibPlacenote.
   If a map is loaded before startSession is called, libPlacenote will
   localize against the loaded map without mapping. If not, it will start
   mapping the environment.
   
   - Returns: A Bool that indicates whether LibPlacenote SDK is initialized
   */
  func setIntrinsics (intrinsics: matrix_float3x3) -> Void {
    setIntrinsicsNative(intrinsics)
  }
  
  /**
   Return the current status of the mapping engine
   
   - Returns: A MappingStatus that indicates the current status of LibPlacenote mapping engine
   */
  public func getMappingStatus () -> MappingStatus {
    let status: Int32 = PNGetStatus()
    var statusEnum: MappingStatus = MappingStatus.waiting
    switch status {
    case 0:
      statusEnum = MappingStatus.waiting
    case 1:
      statusEnum = MappingStatus.running
    case 2:
      statusEnum = MappingStatus.lost
    default:
      let stat = String(format: "Unknown status: %d", status)
      os_log("%@" ,log: OSLog.default, type: .error, stat) //TODO: printout status. currently getting garbled memory when API not active
    }
    
    return statusEnum;
  }
  
  /**
   Return the current 6DoF inertial pose of the LibPlacenote pose tracker against its map
   
   - Returns: A matrix_float4x4 that describes the inertial pose
   */
  public func getPose() -> matrix_float4x4 {
    let poseNative: PNTransform = getPoseNative()
    let pose: matrix_float4x4  = matrix_float4x4.fromPNTransform(pose: poseNative)
    
    return pose;
  }
  
  /**
   Return a position vector3 in the current ARKit frame transformed into the inertial frame w.r.t the current Placenote Map
   
   - Returns: A SCNVector3 that describes the position of an object in the inertial pose.
   */
  public func processPosition(pose : SCNVector3) -> SCNVector3 {
    var tfInARKit :  matrix_float4x4 = matrix_identity_float4x4
    tfInARKit.columns.3.x = pose.x
    tfInARKit.columns.3.y = pose.y
    tfInARKit.columns.3.z = pose.z
    let tfInPN : matrix_float4x4 = currTransform*tfInARKit
    
    if(currStatus != MappingStatus.running) {
      os_log("Processing position while map is not localized. Returning input value", log: OSLog.default, type: .error)
    }
    
    return tfInPN.position()
  }
  
  
  /**
   Return a transform in the current ARKit frame transformed into the inertial frame w.r.t the current Placenote Map
   
   - Returns: A SCNMatrix4 that describes the position and orientation of an object in the inertial pose.
   */
  public func processPose(pose: SCNMatrix4) -> SCNMatrix4 {
    let tfInARKit :  matrix_float4x4 = matrix_float4x4(pose)
    let tfInPN : SCNMatrix4 = SCNMatrix4(currTransform*tfInARKit)
    
    if(currStatus != MappingStatus.running) {
      os_log("Processing position while map is not localized. Returning input value", log: OSLog.default, type: .error)
    }
    
    return tfInPN
  }
  
  
  /**
   Return a transform in the current ARKit frame transformed into the inertial frame w.r.t the current Placenote Map
   
   - Returns: A matrix_float4x4 that describes the position and orientation of an object in the inertial pose.
   */
  public func processPose(pose: matrix_float4x4) -> matrix_float4x4 {
    if(currStatus != MappingStatus.running) {
      os_log("Processing position while map is not localized. Returning input value", log: OSLog.default, type: .error)
    }
    return currTransform*pose
  }
  
  
  /**
   Return an array of 3d points in the inertial map frame that LibPlacenote is currently measuring
   
   - Returns: A Array<PNFeaturePoint> that contains a set of feature points in the
              inertial map frame that LibPlacenote is currently tracking
   */
  public func getTrackedLandmarks() -> Array<PNFeaturePoint> {
    var pointArray: [PNFeaturePoint] = []
    let feature: PNFeaturePoint = PNFeaturePoint()
    
    let featureCount: Int32 = PNGetTrackedLandmarks(UnsafeMutablePointer(mutating: pointArray), 0)
    pointArray = Array(repeating: feature, count: Int(featureCount))
    PNGetTrackedLandmarks(UnsafeMutablePointer(mutating: pointArray), featureCount)
    
    return pointArray
  }
  
  
  /**
   Return the entire map that LibPlacenote has generated over the current session
   
   - Returns: A Array<PNFeaturePoint> that contains a set of feature points in the
              inertial map frame that LibPlacenote generated within this mapping session
   */
  public func getAllLandmarks() -> Array<PNFeaturePoint> {
    var pointArray: [PNFeaturePoint] = []
    let feature: PNFeaturePoint = PNFeaturePoint()
    
    let featureCount: Int32 = PNGetAllLandmarks(UnsafeMutablePointer(mutating: pointArray), 0)
    pointArray = Array(repeating: feature, count: Int(featureCount))
    PNGetAllLandmarks(UnsafeMutablePointer(mutating: pointArray), featureCount)
    
    return pointArray
  }
  
  
  /**
   Return the entire map that LibPlacenote has generated over the current session
   
   - Returns: A Array<PNFeaturePoint> that contains a set of feature points in the
   inertial map frame that LibPlacenote generated within this mapping session
   */
  public func setFrame(image: CVImageBuffer, pose: matrix_float4x4) -> Void {
    setFrameNative(image, pose.position(), pose.rotation());
  }
  
  /**
   Function to stop a running mapping session, and upload it to the LibPlacenote Map Cloud
   upon saving succesfully. Note that this will reset the generated map,
   therefore saveMap should be called before you call this function
   */
  public func stopSession() {
    PNStopSession()
    multiDelegate.onStatusChange(prevStatus: prevStatus, currStatus: MappingStatus.waiting)
    prevStatus = MappingStatus.waiting
  }
  
  
  /**
   Save the map that LibPlacenote is generating in its current mapping session
   
   - Parameter savedCb: an asynchronous callback that indicates whether a map has been saved and what the unique mapId is
   - Parameter uploadProgressCb: progress of the automatic synchronization with Placenote Map Cloud
   */
  public func saveMap(savedCb: @escaping SaveMapCallback, uploadProgressCb: @escaping FileTransferCallback) -> Void {
    let cbCtx: CallbackContext = CallbackContext(id: UUID().uuidString, ptr: self)
    
    saveMapCbDict[cbCtx.callbackId] = savedCb
    mapTransferCbDict[cbCtx.callbackId] = uploadProgressCb
    ctxDict[cbCtx.callbackId] = cbCtx
    
    let anUnmanaged = Unmanaged<CallbackContext>.passUnretained(ctxDict[cbCtx.callbackId]!)
    let ctxPtr = UnsafeMutableRawPointer(anUnmanaged.toOpaque())
    
    os_log("Saving Map")
    PNAddMap({(result: UnsafeMutablePointer<PNCallbackResult>?, swiftContext: UnsafeMutableRawPointer?) -> Void in
      let success = result?.pointee.success
      let cbReturnedCtx = Unmanaged<CallbackContext>.fromOpaque(swiftContext!).takeUnretainedValue()
      let callbackId = cbReturnedCtx.callbackId
      let libPtr = cbReturnedCtx.libPtr
      
      if (success != nil && success!) {
        let mapId: String? = String(cString: (result?.pointee.msg)!, encoding: String.Encoding.ascii)
        os_log("Added map to the database! Response: %@", mapId!)
        
        PNSaveMap(mapId, {(status: UnsafeMutablePointer<PNTransferStatus>?, swiftContext2: UnsafeMutableRawPointer?) -> Void in
          let cbCtx3 = Unmanaged<CallbackContext>.fromOpaque(swiftContext2!).takeUnretainedValue()
          let complete = status?.pointee.completed
          let faulted = status?.pointee.faulted
          let bytesTransferred = status?.pointee.bytesTransferred
          let bytesTotal = status?.pointee.bytesTotal
          
          DispatchQueue.main.async(execute: {() -> Void in
            if (complete != nil && complete!) {
              os_log("Uploaded map!")
              cbCtx3.libPtr.mapTransferCbDict[cbCtx3.callbackId]!(true, false, 1)
              cbCtx3.libPtr.mapTransferCbDict.removeValue(forKey: cbCtx3.callbackId)
              cbCtx3.libPtr.ctxDict.removeValue(forKey: cbCtx3.callbackId)
            } else if (faulted != nil && faulted!) {
              os_log("Failed to upload map!", log: OSLog.default, type: .fault )
              cbCtx3.libPtr.mapTransferCbDict[cbCtx3.callbackId]!(false, true, 0)
              cbCtx3.libPtr.mapTransferCbDict.removeValue(forKey: cbCtx3.callbackId)
              cbCtx3.libPtr.ctxDict.removeValue(forKey: cbCtx3.callbackId)
            } else {
              os_log("Uploading map!")
              cbCtx3.libPtr.mapTransferCbDict[cbCtx3.callbackId]!(
                false, false, Float(bytesTransferred!)/Float(bytesTotal!)
              )
            }
          })
        }, swiftContext)
        
        os_log("Saved Map")
        DispatchQueue.main.async(execute: {() -> Void in
          libPtr.saveMapCbDict[callbackId]!(mapId!)
          libPtr.saveMapCbDict.removeValue(forKey: callbackId)
        })
      } else {
        let errorMsg: String? = String(cString: (result?.pointee.msg)!, encoding: String.Encoding.ascii)
        os_log("Failed to add the map! Error msg: %@", log: OSLog.default, type: .error,  errorMsg!)
        
        DispatchQueue.main.async(execute: {() -> Void in
          libPtr.saveMapCbDict[callbackId]!(nil)
          libPtr.saveMapCbDict.removeValue(forKey: callbackId)
          libPtr.ctxDict.removeValue(forKey: callbackId)
        })
      }
    }, ctxPtr)
  }
  
  /**
   Delete a map given its mapId from the filesystem and LibPlacenote Map Cloud
   
   - Parameter mapId: ID of the map to be deleted from the filesystem and the Map Cloud
   - Parameter deletedCb: async callback to indicate whether the map is successfully deleted
   */
  public func deleteMap(mapId: String, deletedCb : @escaping DeleteMapCallback) {
    let cbCtx: CallbackContext = CallbackContext(id: UUID().uuidString, ptr: self)
    
    deleteMapCbDict[cbCtx.callbackId] = deletedCb
    ctxDict[cbCtx.callbackId] = cbCtx
    let anUnmanaged = Unmanaged<CallbackContext>.passUnretained(ctxDict[cbCtx.callbackId]!)
    let ctxPtr = UnsafeMutableRawPointer(anUnmanaged.toOpaque())
    
    os_log("Deleting Map")
    PNDeleteMap(mapId, {(result: UnsafeMutablePointer<PNCallbackResult>?, swiftContext: UnsafeMutableRawPointer?) -> Void in
      let cbReturnedCtx = Unmanaged<CallbackContext>.fromOpaque(swiftContext!).takeUnretainedValue()
      let callbackId = cbReturnedCtx.callbackId
      let libPtr = cbReturnedCtx.libPtr
      let success = result?.pointee.success
      
      DispatchQueue.main.async(execute: {() -> Void in
        if (success != nil && success!) {
          os_log("Map deleted!")
          libPtr.deleteMapCbDict[callbackId]!(true)
        } else {
          os_log("Failed to delete map!", log: OSLog.default, type: .error)
          libPtr.deleteMapCbDict[callbackId]!(false)
        }
        libPtr.deleteMapCbDict.removeValue(forKey: callbackId)
        libPtr.ctxDict.removeValue(forKey: callbackId)
      })
      
    }, ctxPtr)
  }
  
  /**
   Load a map given its mapId. If the map does not exist in the filesystem, tries to download
   from the Placenote Map Cloud
   
   - Parameter mapId: ID of the map to be deleted from the filesystem and the Map Cloud
   - Parameter deletedCb: async callback to indicate whether the map is successfully deleted
   */
  public func loadMap(mapId: String, downloadProgressCb : @escaping FileTransferCallback) {
    let cbCtx: CallbackContext = CallbackContext(id: UUID().uuidString, ptr: self)
    
    mapTransferCbDict[cbCtx.callbackId] = downloadProgressCb
    ctxDict[cbCtx.callbackId] = cbCtx
    let anUnmanaged = Unmanaged<CallbackContext>.passUnretained(ctxDict[cbCtx.callbackId]!)
    let ctxPtr = UnsafeMutableRawPointer(anUnmanaged.toOpaque())
    
    os_log("Loading Map")
    PNLoadMap(mapId, {(status: UnsafeMutablePointer<PNTransferStatus>?, swiftContext: UnsafeMutableRawPointer?) -> Void in
      let cbRetCtx = Unmanaged<CallbackContext>.fromOpaque(swiftContext!).takeUnretainedValue()
      let libPtr = cbRetCtx.libPtr
      let callbackId = cbRetCtx.callbackId
      let completed = status?.pointee.completed
      let faulted = status?.pointee.faulted
      let bytesTransferred = status?.pointee.bytesTransferred
      let bytesTotal = status?.pointee.bytesTotal
      
      DispatchQueue.main.async(execute: {() -> Void in
        if (completed!) {
          os_log("Map loaded!")
          libPtr.mapTransferCbDict[callbackId]!(true, false, 1)
          libPtr.mapTransferCbDict.removeValue(forKey: callbackId)
          libPtr.ctxDict.removeValue(forKey: callbackId)
        } else if (faulted!) {
          os_log("Failed to load map!", log: OSLog.default, type: .fault)
          libPtr.mapTransferCbDict[callbackId]!(false, true, 0)
          libPtr.mapTransferCbDict.removeValue(forKey: callbackId)
          libPtr.ctxDict.removeValue(forKey: callbackId)
        } else {
          var progress:Float = 0
          if (bytesTotal! > 0) {
            progress = Float(bytesTransferred!)/Float(bytesTotal!)
          }
          libPtr.mapTransferCbDict[callbackId]!(false, false, progress)
        }
      })
    }, ctxPtr)
  }
  
  /**
   Fetch a list of maps filtered with name identifier.
   
   - Parameter name: name of the map you're looking for.
   - Parameter listCb: async callback that returns the map list for based on parameters specified in search.
   */
  public func searchMaps(name: String, listCb: @escaping ListMapCallback) {
    let ms: MapSearch = MapSearch ();
    ms.name = name;
    searchMaps (searchParams: ms, listCb: listCb);
  }
  
  /**
   Fetch a list of maps filtered with Date range limits.
   
   - Parameter newerThan: limit the list of returned maps to be newer than this Date.
   - Parameter olderThan: limit the list of returned maps to be older than this Date.
   - Parameter listCb: async callback that returns the map list for based on parameters specified in search.
   */
  public func searchMaps(newerThan: Date, olderThan: Date, listCb: @escaping ListMapCallback) {
    let ms: MapSearch = MapSearch ();
    ms.setNewerThan(dt: newerThan);
    ms.setOlderThan(dt: olderThan);
    searchMaps (searchParams: ms, listCb: listCb);
  }
  
  /**
   Fetch a list of maps filtered within the radius of a circle around the GPS location passed in.
   
   - Parameter latitude: latitude of the neighbourhood center for the map search.
   - Parameter longitude: longitude of the neighbourhood center for the map search.
   - Parameter radius: radius of the neighbourhood center for the map search.
   - Parameter listCb: async callback that returns the map list for based on parameters specified in search
   */
  public func searchMaps(latitude: Double, longitude: Double, radius: Double, listCb: @escaping ListMapCallback) {
    let ms: MapSearch = MapSearch ();
    ms.location = MapLocationSearch ();
    ms.location!.latitude = latitude;
    ms.location!.longitude = longitude;
    ms.location!.radius = radius;
    searchMaps (searchParams: ms, listCb: listCb);
  }
  
  /**
   Fetch a list of maps filtered within the radius of a circle around the GPS location passed in.
   
   - Parameter userdataQuery: see "MapSearch.userdataQuery" for details.
   */
  public func searchMapsByUserData(userDataQuery: String, listCb: @escaping ListMapCallback) {
    let ms: MapSearch = MapSearch ();
    ms.userdataQuery = userDataQuery;
    searchMaps (searchParams: ms, listCb: listCb);
  }
  
  /**
   Fetch a list of maps filtered by some search parameters.
   
   - Parameter search: parameters to constrain the map search. See MapSearch for details.
   - Parameter listCb: async callback that returns the map list for based on parameters specified in search.
   */
  public func searchMaps(searchParams: MapSearch, listCb: @escaping ListMapCallback) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let searchData = try? encoder.encode(searchParams);
    if (searchData == nil) {
      listCb(false, [:]);
      return;
    }
    
    let cbCtx: CallbackContext = CallbackContext(id: UUID().uuidString, ptr: self)
    listMapCbDict[cbCtx.callbackId] = listCb
    ctxDict[cbCtx.callbackId] = cbCtx
    let anUnmanaged = Unmanaged<CallbackContext>.passUnretained(ctxDict[cbCtx.callbackId]!)
    let ctxPtr = UnsafeMutableRawPointer(anUnmanaged.toOpaque())
    
    let searchJson: String = String(data: searchData!, encoding: .utf8)!;
    print("searchJson:\n" + searchJson);
    PNSearchMaps(searchJson, {(result: UnsafeMutablePointer<PNCallbackResult>?, swiftContext: UnsafeMutableRawPointer?) -> Void in
      let success = result?.pointee.success
      let cbReturnedCtx = Unmanaged<CallbackContext>.fromOpaque(swiftContext!).takeUnretainedValue()
      let libPtr = cbReturnedCtx.libPtr
      let callbackId = cbReturnedCtx.callbackId
      
      if (success != nil && success!) {
        let newMapList: String? = String(cString: (result?.pointee.msg)!, encoding: String.Encoding.ascii)
        
        var placeArray: [String: NSArray]
        var placeIdMap:[String: MapMetadata] = [:]
        if let data = newMapList?.data(using: .utf8) {
          do {
            placeArray = (try JSONSerialization.jsonObject(with: data, options: []) as? [String: NSArray])!
            let places = placeArray["places"]!
            if (places.count > 0) {
              for i in 0...(places.count-1) {
                let place = places[i] as! [String : Any]
                let placeId = place["placeId"] as! String
                let metadataJson = place["metadata"] as! [String:Any]
                let locationJson = metadataJson["location"] as? [String:Double]
                
                let metadata = MapMetadata()
                metadata.created = metadataJson["created"] as? UInt64
                metadata.name = metadataJson["name"] as? String
                if (locationJson != nil) {
                  metadata.location = MapLocation()
                  metadata.location?.latitude = locationJson!["latitude"]!
                  metadata.location?.longitude = locationJson!["longitude"]!
                  metadata.location?.altitude = locationJson!["altitude"]!
                }
                metadata.userdata = metadataJson["userdata"]
                
                placeIdMap[placeId] = metadata
              }
            }
          } catch {
            os_log("Canot parse file list: %@", log: OSLog.default, type: .error, error.localizedDescription)
          }
        }
        
        DispatchQueue.main.async(execute: {() -> Void in
          libPtr.mapList = placeIdMap
          libPtr.listMapCbDict[callbackId]!(true, placeIdMap)
        })
      } else {
        let errorMsg: String? = String(cString: (result?.pointee.msg)!, encoding: String.Encoding.ascii)
        os_log("Failed to fetch the map list! Error msg: %@", log: OSLog.default, type: .error, errorMsg!)
        
        DispatchQueue.main.async(execute: {() -> Void in
          libPtr.listMapCbDict[callbackId]!(false, [:])
        })
      }
      
      DispatchQueue.main.async(execute: {() -> Void in
        libPtr.listMapCbDict.removeValue(forKey: callbackId)
        libPtr.ctxDict.removeValue(forKey: callbackId)
      })
    }, ctxPtr)
  }
  
  /**
   Fetch of list of map IDs that is associated with the given API Key
   
   - Parameter listCb: async callback that returns the map list for a API Key
   */
  public func fetchMapList(listCb: @escaping ListMapCallback) {
    let cbCtx: CallbackContext = CallbackContext(id: UUID().uuidString, ptr: self)
    
    listMapCbDict[cbCtx.callbackId] = listCb
    ctxDict[cbCtx.callbackId] = cbCtx
    let anUnmanaged = Unmanaged<CallbackContext>.passUnretained(ctxDict[cbCtx.callbackId]!)
    let ctxPtr = UnsafeMutableRawPointer(anUnmanaged.toOpaque())
    
    PNListMaps({(result: UnsafeMutablePointer<PNCallbackResult>?, swiftContext: UnsafeMutableRawPointer?) -> Void in
      let success = result?.pointee.success
      let cbReturnedCtx = Unmanaged<CallbackContext>.fromOpaque(swiftContext!).takeUnretainedValue()
      let libPtr = cbReturnedCtx.libPtr
      let callbackId = cbReturnedCtx.callbackId
      
      if (success != nil && success!) {
        let newMapList: String? = String(cString: (result?.pointee.msg)!, encoding: String.Encoding.ascii)
        os_log("Map list fetched from the database! Response: %@", newMapList!)
      
        var placeArray: [String: NSArray]
        var placeIdMap:[String: MapMetadata] = [:]
        if let data = newMapList?.data(using: .utf8) {
          do {
            placeArray = (try JSONSerialization.jsonObject(with: data, options: []) as? [String: NSArray])!
            let places = placeArray["places"]!
            if (places.count > 0) {
              for i in 0...(places.count-1) {
                let place = places[i] as! [String : Any]
                let placeId = place["placeId"] as! String
                let metadataJson = place["metadata"] as! [String:Any]
                let locationJson = metadataJson["location"] as? [String:Double]

                let metadata = MapMetadata()
                metadata.created = metadataJson["created"] as? UInt64
                metadata.name = metadataJson["name"] as? String
                if (locationJson != nil) {
                  metadata.location = MapLocation()
                  metadata.location?.latitude = locationJson!["latitude"]!
                  metadata.location?.longitude = locationJson!["longitude"]!
                  metadata.location?.altitude = locationJson!["altitude"]!
                }
                metadata.userdata = metadataJson["userdata"]

                placeIdMap[placeId] = metadata
              }
            }
          } catch {
            os_log("Canot parse file list: %@", log: OSLog.default, type: .error, error.localizedDescription)
          }
        }

        DispatchQueue.main.async(execute: {() -> Void in
          libPtr.mapList = placeIdMap
          libPtr.listMapCbDict[callbackId]!(true, placeIdMap)
        })
      } else {
        let errorMsg: String? = String(cString: (result?.pointee.msg)!, encoding: String.Encoding.ascii)
        os_log("Failed to fetch the map list! Error msg: %@", log: OSLog.default, type: .error, errorMsg!)
        
        DispatchQueue.main.async(execute: {() -> Void in
          libPtr.listMapCbDict[callbackId]!(false, [:])
        })
      }
      
      DispatchQueue.main.async(execute: {() -> Void in
        libPtr.listMapCbDict.removeValue(forKey: callbackId)
        libPtr.ctxDict.removeValue(forKey: callbackId)
      })
    }, ctxPtr)
  }
  
  /**
   Get the metadata for the given map, which will be returned as Libplacenote.metadata with metadata
  
   - Parameter mapId: ID of the map
               getMetadataCb: async callback that returns meta in the form of Libplacenote.metadata. Metadata is empty if the mapid is incorrect
                or does not exist
   */
  
  public func getMapMetadata (mapId: String, getMetadataCb: @escaping GetMetadataCallback) -> Void {
    
    let cbCtx: CallbackContext = CallbackContext(id: UUID().uuidString, ptr: self)
    getMetadataCbDict[cbCtx.callbackId] = getMetadataCb
    ctxDict[cbCtx.callbackId] = cbCtx

    let anUnmanaged = Unmanaged<CallbackContext>.passUnretained(ctxDict[cbCtx.callbackId]!)
    let ctxPtr = UnsafeMutableRawPointer(anUnmanaged.toOpaque())
    
    PNGetMetadata(mapId, {(result: UnsafeMutablePointer<PNCallbackResult>?, swiftContext: UnsafeMutableRawPointer?) -> Void in
      let success = result?.pointee.success
      let cbReturnedCtx = Unmanaged<CallbackContext>.fromOpaque(swiftContext!).takeUnretainedValue()
      let libPtr = cbReturnedCtx.libPtr
      let callbackId = cbReturnedCtx.callbackId
      if (success != nil && success! && result?.pointee.msg != nil) {
        
        let metadataString = String(cString: (result?.pointee.msg)!, encoding: String.Encoding.ascii)
        let data = metadataString!.data(using: .utf8)
        
        do {
          let metadata: LibPlacenote.MapMetadata = LibPlacenote.MapMetadata()

          if (data != nil) {
            let dataJson = try JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any?]
            let metadataJson = dataJson!["metadata"] as! [String: Any?]
            metadata.created = metadataJson["created"] as? UInt64
            metadata.name = metadataJson["name"] as? String
            metadata.location = LibPlacenote.MapLocation()
            
            metadata.location?.latitude = (metadataJson["location"]! as! [String: Double])["latitude"]!
            metadata.location?.longitude = (metadataJson["location"] as! [String: Double])["longitude"]!
            metadata.location?.altitude = (metadataJson["location"] as! [String: Double])["altitude"]!
            metadata.userdata = metadataJson["userdata"] as? [String: Any?]
            
          }
          else {
            os_log("Failed to convert received map metadata to string", log: OSLog.default, type: .error)
          }
          DispatchQueue.main.async(execute: {() -> Void in
            libPtr.getMetadataCbDict[callbackId]!(true, metadata)
          })
        }
        catch {
          os_log("Failed to convert received map metadata", log: OSLog.default, type: .error)
        }
      }
      else {
        let errorMsg: String? = String(cString: (result?.pointee.msg)!, encoding: String.Encoding.ascii)
        os_log("Failed to receive map metadata! Error msg: %@", log: OSLog.default, type: .error, errorMsg!)
        
        DispatchQueue.main.async(execute: {() -> Void in
          let metadata: LibPlacenote.MapMetadata = LibPlacenote.MapMetadata() //empty metadata
          libPtr.getMetadataCbDict[callbackId]!(false , metadata)
        })
      }
      
    },ctxPtr)
  }


  /**
   Set the metadata for the given map, which will be returned as the value of the
   dictionary of ListMapCallback. The metadata must be a valid JSON value, object,
   or array a serialized string.
   
   - Parameter mapId: ID of the map
   - Parameter metadataJson: Serialized JSON metadata
   - Returns: False if the SDK was not initialized, or metadataJson was invalid.
   True otherwise.
   */
  public func setMapMetadata(mapId: String, metadata: MapMetadataSettable) -> Bool {
    return setMapMetadata(mapId: mapId, metadata: metadata, metadataSavedCb: {(success:Bool) -> Void in
    })
  }


  /**
   Set the metadata for the given map, which will be returned as the value of the
   dictionary of ListMapCallback. The metadata must be a valid JSON value, object,
   or array a serialized string.

   - Parameter mapId: ID of the map
   - Parameter metadataJson: Serialized JSON metadata
   - Parameter metadataSavedCb: Callback to indicate the success/failure of the setMapMetadata result
   - Returns: False if the SDK was not initialized, or metadataJson was invalid.
     True otherwise.
   */
  public func setMapMetadata(mapId: String, metadata: MapMetadataSettable, metadataSavedCb: @escaping MetadataSavedCallback) -> Bool {
    let cbCtx: CallbackContext = CallbackContext(id: UUID().uuidString, ptr: self)
    
    setMetadataCbDict[cbCtx.callbackId] = metadataSavedCb
    ctxDict[cbCtx.callbackId] = cbCtx
    let anUnmanaged = Unmanaged<CallbackContext>.passUnretained(ctxDict[cbCtx.callbackId]!)
    let ctxPtr = UnsafeMutableRawPointer(anUnmanaged.toOpaque())
    
    var metadataDict:[String: Any] = [:]
    if (metadata.name != nil) {
      metadataDict["name"] = metadata.name!
    }
    if (metadata.location != nil) {
      var location:[String: Any] = [:]
      location["latitude"] = metadata.location?.latitude
      location["longitude"] = metadata.location?.longitude
      location["altitude"] = metadata.location?.altitude
      metadataDict["location"] = location
    }
    if (metadata.userdata != nil) {
      metadataDict["userdata"] = metadata.userdata!
    }

    do {
      let metadataData = try JSONSerialization.data(withJSONObject: metadataDict)
      let metadataJson = String(data: metadataData, encoding: String.Encoding.utf8)

      let retCode: Int32 = PNSetMetadata(mapId, metadataJson,
        {(result: UnsafeMutablePointer<PNCallbackResult>?, swiftContext: UnsafeMutableRawPointer?) -> Void in
          let success = result?.pointee.success
          let cbReturnedCtx = Unmanaged<CallbackContext>.fromOpaque(swiftContext!).takeUnretainedValue()
          let libPtr = cbReturnedCtx.libPtr
          let callbackId = cbReturnedCtx.callbackId
          
          if (success != nil && success!) {
            DispatchQueue.main.async(execute: {() -> Void in
              libPtr.setMetadataCbDict[callbackId]!(true)
            })
          } else {
            let errorMsg: String? = String(cString: (result?.pointee.msg)!, encoding: String.Encoding.ascii)
            os_log("Failed to set the map metadata! Error msg: %@", log: OSLog.default, type: .error, errorMsg!)
            
            DispatchQueue.main.async(execute: {() -> Void in
              libPtr.setMetadataCbDict[callbackId]!(false)
            })
          }
          
          DispatchQueue.main.async(execute: {() -> Void in
            libPtr.setMetadataCbDict.removeValue(forKey: callbackId)
            libPtr.ctxDict.removeValue(forKey: callbackId)
          })
        },
        ctxPtr
      )
      
      return retCode == 0
    } catch {
      print (error)
      return false
    }
  }
  
  
  /**
   Start recording a dataset to be reported to the Placenote team. Recording is automatically
   stopped when stopSession() is called.

   - Parameter uploadProgressCb: callback to monitor upload progress of the dataset
   */
  public func startReportRecord(uploadProgressCb: @escaping FileTransferCallback) -> Void {
    let cbCtx: CallbackContext = CallbackContext(id: UUID().uuidString, ptr: self)
    
    mapTransferCbDict[cbCtx.callbackId] = uploadProgressCb
    ctxDict[cbCtx.callbackId] = cbCtx
    
    let anUnmanaged = Unmanaged<CallbackContext>.passUnretained(ctxDict[cbCtx.callbackId]!)
    let ctxPtr = UnsafeMutableRawPointer(anUnmanaged.toOpaque())
    
    PNStartRecordDataset({(status: UnsafeMutablePointer<PNTransferStatus>?, swiftContext: UnsafeMutableRawPointer?) -> Void in
      let cbRetCtx = Unmanaged<CallbackContext>.fromOpaque(swiftContext!).takeUnretainedValue()
      let libPtr = cbRetCtx.libPtr
      let callbackId = cbRetCtx.callbackId
      let completed = status?.pointee.completed
      let faulted = status?.pointee.faulted
      let bytesTransferred = status?.pointee.bytesTransferred
      let bytesTotal = status?.pointee.bytesTotal
      
      DispatchQueue.main.async(execute: {() -> Void in
        if (completed!) {
          os_log("Dataset uploaded!")
          libPtr.mapTransferCbDict[callbackId]!(true, false, 1)
          libPtr.mapTransferCbDict.removeValue(forKey: callbackId)
          libPtr.ctxDict.removeValue(forKey: callbackId)
        } else if (faulted!) {
          os_log("Failed to upload dataset!", log: OSLog.default, type: .fault)
          libPtr.mapTransferCbDict[callbackId]!(false, true, 0)
          libPtr.mapTransferCbDict.removeValue(forKey: callbackId)
          libPtr.ctxDict.removeValue(forKey: callbackId)
        } else {
          var progress:Float = 0
          if (bytesTotal! > 0) {
            progress = Float(bytesTransferred!)/Float(bytesTotal!)
          }
          libPtr.mapTransferCbDict[callbackId]!(false, false, progress)
        }
      })
    }, ctxPtr)
  }
  
}
