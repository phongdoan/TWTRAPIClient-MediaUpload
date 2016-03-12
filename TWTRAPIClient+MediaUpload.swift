//
//  TWTRAPIClient+MediaUpload.swift
//  Cinemaker
//
//  Created by Max Rozdobudko on 1/28/16.
//  Copyright © 2016 Max Rozdobudko. All rights reserved.
//
//  http://github.com/rozd/TWTRAPIClient+MediaUpload
//
//  Distributed under MIT License http://opensource.org/licenses/MIT
//

import Foundation
import TwitterKit

public enum TWTRMediaUploadStatus
{
    case Init(totalBytes:Int, mimeType:String);
    case Inited(mediaId:String);
    case Append(mediaId:String, totalSegmentCount:Int);
    case Appended(mediaId:String);
    case SegmentAppend(mediaId:String, segmentIndex:Int, remainingSegmentCount:Int);
    case SegmentAppended(mediaId:String, segmentIndex:Int);
    case Finalize(mediaId:String);
    case Finalized(mediaId:String);
    case Error(mediaId:String?, message:String);
    
    func toString() -> String
    {
        switch (self)
        {
            case .Init(let totalBytes, let mimeType) :
                return "TWTRMediaUploadStatus.Init(totalBytes:\(totalBytes), mimeType:\(mimeType))";
            
            case .Inited(let mediaId) :
                return "TWTRMediaUploadStatus.Inited(mediaId:\(mediaId))";
            
            case .Append(let mediaId, let totalSegmentCount) :
                return "TWTRMediaUploadStatus.Append(mediaId:\(mediaId), totalSegmentCount:\(totalSegmentCount))";
                
            case .Appended(let mediaId) :
                return "TWTRMediaUploadStatus.Appended(mediaId:\(mediaId))";
                
            case .SegmentAppend(let mediaId, let segmentIndex, let remainingSegmentCount) :
                return "TWTRMediaUploadStatus.SegmentAppend(mediaId:\(mediaId), segementIndex:\(segmentIndex), remainingSegmentCount:\(remainingSegmentCount))";
                
            case .SegmentAppended(let mediaId, let segmentIndex) :
                return "TWTRMediaUploadStatus.SegmentAppended(mediaId:\(mediaId), segmentIndex: \(segmentIndex))";
                
            case .Finalize(let mediaId) :
                return "TWTRMediaUploadStatus.Finalize(mediaId:\(mediaId))";
                
            case .Finalized(let mediaId) :
                return "TWTRMediaUploadStatus.Finalized(mediaId:\(mediaId))";
                
            case .Error(let mediaId, let message) :
                return "TWTRMediaUploadStatus.Error(mediaId:\(mediaId), message:\(message))";
        }
    }
}

public typealias TWTRStatusUpdateCallback = (tweet:TWTRTweet?, error:NSError?) -> Void;

public typealias TWTRMediaUploadCallback = (mediaId:String?, error:NSError?) -> Void;

public typealias TWTRMediaUploadStatusCallback = (status:TWTRMediaUploadStatus) -> Void;

/**
 * Used to wrap closure to store in associated objects.
 */
private class ClosureWrapper : NSObject, NSCopying
{
    convenience init(closure: TWTRMediaUploadStatusCallback?)
    {
        self.init()
        self.closure = closure;
    }
    
    var closure:TWTRMediaUploadStatusCallback?;
    
    @objc
    func copyWithZone(zone: NSZone) -> AnyObject
    {
        let wrapper: ClosureWrapper = ClosureWrapper()
        wrapper.closure = self.closure;
        
        return wrapper
    }
}

extension TWTRAPIClient
{
    private struct AssociatedKeys
    {
        static var MediaUploadCallback:String = "MediaUploadCallback";
    }

    // MARK: Properties

    var mediaUploadStatusCallback: TWTRMediaUploadStatusCallback?
    {
        get
        {
            if let wrapper = objc_getAssociatedObject(self, &AssociatedKeys.MediaUploadCallback) as? ClosureWrapper
            {
                return wrapper.closure;
            }
            
            return nil;
        }
        set
        {
            objc_setAssociatedObject(self, &AssociatedKeys.MediaUploadCallback, ClosureWrapper(closure: newValue), objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN);
        }
    }
    
    // MARK: Extension API

    func statusUpdate(status:String, mediaURL:NSURL, mimeType:String?, callback:TWTRStatusUpdateCallback)
    {
        if let data:NSData = NSData(contentsOfURL: mediaURL)
        {
            self.statusUpdate(status, mediaData: data, mimeType: mimeType, callback: callback);
        }
        else
        {
            callback(tweet: nil, error: NSError(domain: TWTRErrorDomain, code: TWTRErrorCode.Unknown.rawValue, userInfo: [NSLocalizedDescriptionKey : "Could not read media file"]));
        }
    }

    func statusUpdate(status:String, mediaData:NSData, mimeType:String?, callback:TWTRStatusUpdateCallback)
    {
        let STATUS_UPDATE_ENDPOINT:String = "https://api.twitter.com/1.1/statuses/update.json";

        let resolvedMimeType = mimeType ?? discoverMimeTypeFromData(mediaData);

        self.mediaUploadChunked(mediaData, mimeType: resolvedMimeType) { (mediaId:String?, uploadError:NSError?) -> () in

            if uploadError == nil
            {
                let params =
                [
                    "status" : status,
                    "media_ids" : mediaId!
                ];

                var tweetError:NSError?;
                let request = self.URLRequestWithMethod("POST", URL: STATUS_UPDATE_ENDPOINT, parameters: params, error: &tweetError);

                if tweetError == nil
                {
                    self.sendTwitterRequest(request) { (response:NSURLResponse?, responseData:NSData?, responseError:NSError?) -> Void in

                        if responseError == nil
                        {
                            do
                            {
                                let tweet = try TWTRTweet(JSONDictionary: NSJSONSerialization.JSONObjectWithData(responseData!, options: .MutableContainers) as! [NSObject : AnyObject]);

                                callback(tweet: tweet, error: nil);
                            }
                            catch let parseError as NSError
                            {
                                callback(tweet: nil, error: parseError);
                            }
                            catch
                            {
                                callback(tweet: nil, error: NSError(domain: TWTRAPIErrorDomain, code: TWTRErrorCode.Unknown.rawValue, userInfo: [NSLocalizedDescriptionKey : "Error parsing received Tweet"]));
                            }
                        }
                        else
                        {
                            callback(tweet: nil, error: responseError);
                        }
                    };
                }
                else
                {
                    callback(tweet: nil, error: tweetError);
                }
            }
            else
            {
                callback(tweet: nil, error: uploadError);
            }
        };
    }
    
    func mediaUploadChunked(data:NSData, mimeType:String, callback:TWTRMediaUploadCallback)
    {
        let MEDIA_UPLOAD_ENDPOINT = "https://upload.twitter.com/1.1/media/upload.json";
        
        var chunks:[NSData] = self.separateMediaToChunks(data);
        
        func initUpload(callback:TWTRMediaUploadCallback)
        {
            self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Init(totalBytes: data.length, mimeType: mimeType));
            
            let params =
            [
                "command" : "INIT",
                "total_bytes" : NSNumber(integer: data.length).stringValue,
                "media_type" : mimeType
            ];
            
            var initError:NSError?;
            let request = self.URLRequestWithMethod("POST", URL: MEDIA_UPLOAD_ENDPOINT, parameters: params, error: &initError);
            
            if initError == nil
            {
                self.sendTwitterRequest(request) { (response:NSURLResponse?, responseData:NSData?, responseError:NSError?) -> Void in
                    
                    if responseError == nil
                    {
                        do
                        {
                            let json:NSDictionary? = try NSJSONSerialization.JSONObjectWithData(responseData!, options: .MutableContainers) as? NSDictionary;
                            
                            if let mediaId = json?["media_id_string"] as? NSString
                            {
                                self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Inited(mediaId: mediaId as String));
                                
                                callback(mediaId: mediaId as String, error: nil);
                            }
                            else
                            {
                                self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Error(mediaId: nil, message: "Could not obtain media_id_string from response"));
                                
                                callback(mediaId: nil, error: NSError(domain: TWTRErrorDomain, code: TWTRErrorCode.Unknown.rawValue, userInfo: [NSLocalizedDescriptionKey : "Could not obtain media_id_string from response"]));
                            }
                        }
                        catch let parseError as NSError
                        {
                            self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Error(mediaId: nil, message: parseError.localizedDescription));
                            
                            callback(mediaId: nil, error: parseError);
                        }
                        catch
                        {
                            self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Error(mediaId: nil, message: "Error parsing received data"));
                            
                            callback(mediaId: nil, error: NSError(domain: TWTRAPIErrorDomain, code: TWTRErrorCode.Unknown.rawValue, userInfo: [NSLocalizedDescriptionKey : "Error parsing received data"]));
                        }
                    }
                    else
                    {
                        self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Error(mediaId: nil, message: responseError!.localizedDescription));
                        
                        callback(mediaId: nil, error: responseError);
                    }
                };
            }
            else
            {
                self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Error(mediaId: nil, message: initError!.localizedDescription));
                
                callback(mediaId: nil, error: initError);
            }
        }
        
        func appendChunks(mediaId:String, segmentIndex:Int, callback:TWTRMediaUploadCallback)
        {
            self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Append(mediaId: mediaId, totalSegmentCount: chunks.count));
            
            if chunks.isEmpty
            {
                self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Appended(mediaId: mediaId));
                
                callback(mediaId: mediaId, error: nil);
            }
            else
            {
                let chunk = chunks.removeFirst();
                
                self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.SegmentAppend(mediaId: mediaId, segmentIndex: segmentIndex, remainingSegmentCount: chunks.count));
                
                let params:[String : String] =
                [
                    "command" : "APPEND",
                    "media_id" : mediaId,
                    "segment_index" : String(segmentIndex),
                    "media" : chunk.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0))
                ];
                
                var appendError:NSError?;
                let request = self.URLRequestWithMethod("POST", URL: MEDIA_UPLOAD_ENDPOINT, parameters: params, error: &appendError);
                
                if appendError == nil
                {
                    self.sendTwitterRequest(request) { (response:NSURLResponse?, responseData:NSData?, responseError:NSError?) -> Void in
                        
                        if responseError == nil
                        {
                            self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.SegmentAppended(mediaId: mediaId, segmentIndex: segmentIndex));
                            
                            appendChunks(mediaId, segmentIndex: segmentIndex + 1, callback: callback);
                        }
                        else
                        {
                            self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Error(mediaId: nil, message: responseError!.localizedDescription));
                            
                            callback(mediaId: nil, error: responseError);
                        }
                    };
                }
                else
                {
                    self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Error(mediaId: nil, message: appendError!.localizedDescription));
                    
                    callback(mediaId: nil, error: appendError);
                }
            }
        }
        
        func finalizeUpload(mediaId:String, callback:TWTRMediaUploadCallback)
        {
            self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Finalize(mediaId: mediaId));
            
            let params =
            [
                "command" : "FINALIZE",
                "media_id" : mediaId
            ];
            
            var finalizeError:NSError?;
            let request = self.URLRequestWithMethod("POST", URL: MEDIA_UPLOAD_ENDPOINT, parameters: params, error: &finalizeError);
            
            if finalizeError == nil
            {
                self.sendTwitterRequest(request) { (response:NSURLResponse?, responseData:NSData?, responseError:NSError?) -> Void in
                    
                    if responseError == nil
                    {
                        self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Finalized(mediaId: mediaId));
                        
                        callback(mediaId: mediaId, error: nil);
                    }
                    else
                    {
                        self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Error(mediaId: nil, message: responseError!.localizedDescription));
                        
                        callback(mediaId: nil, error: responseError);
                    }
                }
            }
            else
            {
                self.mediaUploadStatusCallback?(status: TWTRMediaUploadStatus.Error(mediaId: nil, message: finalizeError!.localizedDescription));
                
                callback(mediaId: nil, error: finalizeError);
            }
        }
        
        func checkStatus(mediaId:String, callback:(ready:Bool, error:NSError?) -> ())
        {
            let params =
            [
                "command" : "STATUS",
                "media_id" : mediaId
            ];
            
            var statusError:NSError?;
            let request = self.URLRequestWithMethod("POST", URL: MEDIA_UPLOAD_ENDPOINT, parameters: params, error: &statusError);
            
            if statusError == nil
            {
                self.sendTwitterRequest(request) { (response:NSURLResponse?, responseData:NSData?, responseError:NSError?) -> Void in
                    
                    if responseError == nil
                    {
                        do
                        {
                            let json = try NSJSONSerialization.JSONObjectWithData(responseData!, options: .MutableContainers);

                            callback(ready: true, error: nil);
                        }
                        catch let parseError as NSError
                        {
                            callback(ready: false, error: parseError);
                        }
                        catch
                        {
                            callback(ready: false, error: NSError(domain: TWTRAPIErrorDomain, code: TWTRErrorCode.Unknown.rawValue, userInfo: [NSLocalizedDescriptionKey : "Can't parse received data."]));
                        }
                    }
                    else
                    {
                        callback(ready: false, error: responseError);
                    }
                };
            }
            else
            {
                callback(ready: false, error: statusError);
            }
        }
        
        initUpload() { (mediaId:String?, initError:NSError?) -> () in
            
            if initError == nil
            {
                appendChunks(mediaId!, segmentIndex: 0) { (mediaId:String?, appendError:NSError?) -> () in
                    
                    if appendError == nil
                    {
                        finalizeUpload(mediaId!) { (mediaId:String?, finalizeError:NSError?) -> () in
                            
                            if finalizeError == nil
                            {
                                callback(mediaId: mediaId, error: nil);
                                
//                                checkStatus(mediaId!) { (ready:Bool, statusError:NSError?) -> () in
//
//                                    if statusError == nil
//                                    {
//                                        if ready
//                                        {
//                                            callback(mediaId: mediaId, error: nil);
//                                        }
//                                        else
//                                        {
//                                            // TODO: Let's try check status after timeout (only if upload video)
//
//                                            callback(mediaId: nil, error: NSError(domain: TWTRErrorDomain, code: TWTRErrorCode.Unknown.rawValue, userInfo: nil));
//                                        }
//                                    }
//                                    else
//                                    {
//                                        callback(mediaId: nil, error: statusError);
//                                    }
//                                };
                            }
                            else
                            {
                                callback(mediaId: nil, error: finalizeError);
                            }
                        };
                    }
                    else
                    {
                        callback(mediaId: nil, error: appendError);
                    }
                };
            }
            else
            {
                callback(mediaId: nil, error: initError);
            }
        }
    }

    // MARK: Support functions
    
    func separateMediaToChunks(data:NSData) -> [NSData]
    {
        let MAX_CHUNK_SIZE:Int = 1000 * 1000 * 2; // 2Mb
        
        var chunks:[NSData] = [];
        
        let totalLenght:Float = Float(data.length);
        let chunkLength:Float = Float(MAX_CHUNK_SIZE);
        
        if totalLenght <= chunkLength
        {
            chunks.append(data);
        }
        else
        {
            let count = Int(ceil(totalLenght / chunkLength) - 1);
            
            for i in 0...count
            {
                var range:NSRange!;
                
                if i == count
                {
                    range = NSMakeRange(i * Int(chunkLength), Int(totalLenght) - i * Int(chunkLength));
                }
                else
                {
                    range = NSMakeRange(i * Int(chunkLength), Int(chunkLength));
                }
                
                let chunk = data.subdataWithRange(range);
                
                chunks.append(chunk);
            }
        }
        
        return chunks;
    }

    /// Returns mime-type according to data's heading bytes
    /// Discover based on: http://www.garykessler.net/library/file_sigs.html
    func discoverMimeTypeFromData(data:NSData) -> String
    {
        let bmp:[UInt8] = [0x42, 0x4D];
        let jpg:[UInt8] = [0xFF, 0xD8, 0xFF];
        let png:[UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        let mp4:[UInt8] = [0x66, 0x74, 0x79, 0x70];
        let gif:[UInt8] = [0x47, 0x49, 0x46, 0x38];
        let webp:[UInt8] = [0x52, 0x49, 0x46, 0x46];

        var headChars:[UInt8] = [UInt8](count: 8, repeatedValue: 0);
        data.getBytes(&headChars, length: 8);
        
        if memcmp(bmp, headChars, 2) == 0
        {
            return "image/bmp";
        }
        else if memcmp(jpg, headChars, 3) == 0
        {
            return "image/jpeg";
        }
        else if memcmp(png, headChars, 8) == 0
        {
            return "image/png";
        }
        else if memcmp(gif, headChars, 4) == 0
        {
            return "image/gif";
        }
        else if memcmp(webp, headChars, 4) == 0
        {
            return "image/webp";
        }
        else if memcmp(mp4, [UInt8](headChars[4..<headChars.count]), 4) == 0 // ignoring first 4 byte offset
        {
            return "video/mp4";
        }
        else
        {
            return "application/octet-stream";
        }
    }
}