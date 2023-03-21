//
//  FileUploadViewModel.swift
//  audioToText
//
//  Created by marvel on 2023/3/19.
//

import Foundation
import AVFoundation

let kOpenAIApi = ""
class FileUploadViewModel: ObservableObject {
    @Published var fileName: String = ""
    @Published var fileSize: String = ""
    
    @Published var transcription: String = ""
    
    
    
    /// support video [mp4,mov] and audio format
    /// - Parameter url:
    func uploadFile(url: URL) {
        let fileName = url.lastPathComponent
        self.fileName = fileName
        
        var fileSize = 0
        do {
            let resources = try url.resourceValues(forKeys:[.fileSizeKey])
            fileSize = resources.fileSize!
        } catch {
            print("Error: \(error)")
        }
        self.fileSize = ByteCountFormatter.string(fromByteCount:Int64(fileSize), countStyle: .file)
        
        // check if the file is a video file
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "mp4" || fileExtension == "mov" {
            let asset = AVAsset(url: url)
            let audioTracks = asset.tracks(withMediaType: .audio)
            
            if !audioTracks.isEmpty {
                let composition = AVMutableComposition()
                guard let track = asset.tracks(withMediaType: .audio).first else {
                    return
                }
                let comTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                do {
                    try comTrack?.insertTimeRange(track.timeRange, of: track, at: CMTime.zero)
                } catch let error {
                    print(error.localizedDescription)
                    return
                }
                let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
                session?.outputFileType = .m4a
                
                let outputUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(NSDate().timeIntervalSince1970)-audio.wav")
                session?.outputURL = outputUrl
                session?.exportAsynchronously(completionHandler: {
                    if session?.status == .completed {
                        print("AVAssetExportSessionStatusCompleted")
                        do {
                            let splitFiles = try self.splitAudioFile(inputURL: url, chunkLength: 600)
                            var arr = Array(repeating: "", count: splitFiles.count)
                            
                            for splitFile in splitFiles {
                                
                                debugPrint(splitFile.absoluteString)
                                self.uploadAudioFile(url: splitFile) { text in
                                    DispatchQueue.main.async {
                                        
                                        if let iRange = splitFile.absoluteString.range(of: "chunk") {
                                            let startIndex = iRange.upperBound
                                            let endIndex = splitFile.absoluteString.range(of: ".m4a")!.lowerBound
                                            let iString = splitFile.absoluteString[startIndex..<endIndex]
                                            if let i = Int(iString) {
                                                arr.insert(text ?? "", at: i)
                                            }
                                        }
                                        
                                        self.transcription = arr.joined(separator: "\n")
                                    }
                                }
                            }
                        }catch let error {
                            print("Error splitting audio file: \(error.localizedDescription)")
                        }
                             
                    } else {
                        print("session status: \(session?.status.rawValue ?? 0)")
                    }
                })
                
                return
            }
        }
        self.uploadAudioFile(url: url)
    }
    
    
    /// seperate long audio into small audios
    /// - Parameters:
    ///   - inputURL: location url
    ///   - chunkLength: audio time duration
    /// - Returns: small audios urls
    func splitAudioFile(inputURL: URL, chunkLength: TimeInterval) throws -> [URL] {
        let asset = AVURLAsset(url: inputURL)
        let duration = asset.duration.seconds
        let chunkCount = Int(ceil(duration / chunkLength))
        var outputURLs = [URL]()
        for i in 0..<chunkCount {
            
            let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
            exportSession?.outputFileType = .m4a
            let startTime = CMTime(seconds: Double(i) * chunkLength, preferredTimescale: 1000)
            let endTime = CMTime(seconds: min(Double(i + 1) * chunkLength, duration), preferredTimescale: 1000)
            let timeRange = CMTimeRange(start: startTime, end: endTime)
            let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "chunk\(i).m4a")
            exportSession?.outputURL = outputURL
            exportSession?.timeRange = timeRange
            let semaphore = DispatchSemaphore(value: 0)
            exportSession?.exportAsynchronously(completionHandler: {
                if exportSession?.status == .completed {
                    outputURLs.append(outputURL)
                }
                semaphore.signal()
            })
            semaphore.wait()
        }
        return outputURLs
    }
    
    
    /// upload to openAI
    /// - Parameters:
    ///   - url:
    ///   - completion:
    func uploadAudioFile(url: URL,completion: ((String?) -> ())? = nil) {
        let fileName = url.lastPathComponent
        let boundary = UUID().uuidString
        let body = NSMutableData()
        if let _ = NSData(contentsOf: url) {
            let mimeType = getMimeType(for: url)
            let model = "whisper-1"
            
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(model)\r\n".data(using: .utf8)!)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(try! Data(contentsOf: url))
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        }
        
        // Set the URL, method, and headers
        if let reqUrl = URL(string: "https://api.openai.com/v1/audio/transcriptions") {
            var request = URLRequest(url: reqUrl)
            request.httpMethod = "POST"
            let openaiApiKey = kOpenAIApi
            request.setValue("Bearer \(openaiApiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let session = URLSession.shared
            // Add the file data to the request body and upload the file
            request.httpBody = body as Data
            let task = session.uploadTask(with: request, from: nil, completionHandler: { data, response, error in
                if error == nil {
                    if let jsonData = data {
                        do {
                            if let responseDict = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                                if completion == nil {
                                    self.transcription = self.transcription + (responseDict["text"] as? String ?? "")
                                }
                                let fileManager = FileManager.default
                                let tempDir = NSTemporaryDirectory()
                                do {
                                    let contents = try fileManager.contentsOfDirectory(atPath: tempDir)
                                    let path = "\(tempDir)/\(fileName)"
                                    try? fileManager.removeItem(atPath: path)
                                    completion?(responseDict["text"] as? String ?? "")
                                } catch let error {
                                    print("Error clearing temporary directory: \(error.localizedDescription)")
                                }
                            }
                        } catch {
                            print("Error serializing JSON: \(error.localizedDescription)")
                        }
                    }
                } else {
                    print("Error uploading file: \(error!)")
                }
            })
            task.resume()
        }
    }
    
    
    
    func getAudioDuration(url: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        return duration.seconds
    }
    
    
    func getMimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension as CFString, nil)?.takeRetainedValue() {
            if let mimeType = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimeType as String
            }
        }
        return "application/octet-stream"
    }
    
}
