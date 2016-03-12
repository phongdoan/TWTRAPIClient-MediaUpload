# TWTRAPIClient+MediaUpload
Swift extension for TWTRAPICLinet that provide support for uploading media files to Twitter's server

## Dependencies
 * Swift 2.1
 * TwitterKit 1.15.1

## Usage
The extension provides two functions, first one uploads specified media data on
the Twitter's server, then you will have `mediaId` that you pass into `media_ids`
param (see https://dev.twitter.com/rest/reference/post/statuses/update):
```swift
let client = TWTRAPIClient(userID: userID);

// upload JPEG image
client.mediaUploadChunked(jpegData, mimeType: "image/jpeg") { (mediaId:String?, error:NSError?) in

    if let mediaId = mediaId
    {
        // here you have mediaId that can be used for status update,
        // you create NSURLRequest (or use Alamofire) and pass mediaId as value
        // of "media_ids" param
    }
}
```

The second function combines media upload and update status:
```swift
let client = TWTRAPIClient(userID: userID);

// upload JPEG image
client.statusUpdate(newStatus, mediaURL: mediaURL, mimeType: nil) { (tweet:TWTRTweet?, error:NSError?) in

    if tweet != nil
    {
        // status updated with media
    }
}
```

### Tracking media upload status
To get more information about uploading process you can use `mediaUploadStatusCallback`
that tracks changing status:
```swift
let client = TWTRAPIClient(userID: userID);

client.mediaUploadStatusCallback = { (status:TWTRMediaUploadStatus) in

    switch status
    {
        case .Init(let totalBytes, let mimeType) :
            print("TWTRMediaUploadStatus.Init(totalBytes:\(totalBytes), mimeType:\(mimeType))");

        case .Inited(let mediaId) :
            print("TWTRMediaUploadStatus.Inited(mediaId:\(mediaId))");

        case .Append(let mediaId, let totalSegmentCount) :
            print("TWTRMediaUploadStatus.Append(mediaId:\(mediaId), totalSegmentCount:\(totalSegmentCount))");

        case .Appended(let mediaId) :
            print("TWTRMediaUploadStatus.Appended(mediaId:\(mediaId))");

        case .SegmentAppend(let mediaId, let segmentIndex, let remainingSegmentCount) :
            print("TWTRMediaUploadStatus.SegmentAppend(mediaId:\(mediaId), segementIndex:\(segmentIndex), remainingSegmentCount:\(remainingSegmentCount))");

        case .SegmentAppended(let mediaId, let segmentIndex) :
            print("TWTRMediaUploadStatus.SegmentAppended(mediaId:\(mediaId), segmentIndex: \(segmentIndex))");

        case .Finalize(let mediaId) :
            print("TWTRMediaUploadStatus.Finalize(mediaId:\(mediaId))");

        case .Finalized(let mediaId) :
            print("TWTRMediaUploadStatus.Finalized(mediaId:\(mediaId))");

        case .Error(let mediaId, let message) :
            print("TWTRMediaUploadStatus.Error(mediaId:\(mediaId), message:\(message))");
    }
}

client.mediaUploadChunked(jpegData, mimeType: "image/jpeg") { (mediaId:String?, error:NSError?) in
    // ...
}
```

### Discovering mime-type
A mime type of uploading data could be specified explicitly or be omitted, in
this case it will be discovered from the heading bytes of a media data. Note
that the discovering is not exclusive and only covers formats supported by
Twitter: **PNG**, **JPEG**, **WEBP**, **GIF** and **MP4**:

```swift
let client = TWTRAPICLient(userID: userID);
client.mediaUploadChunked(mediaData, mimeType: nil) { (mediaId:String?, error:NSError?) in
    // mime type will be discovered from the specified mediaData
}
```

## Changelog
 * `0.1.0` Added `mediaUploadStatusCallback` and type aliases for used callbacks, API improvements.
 * `0.0.1` Initial state with basic functionality