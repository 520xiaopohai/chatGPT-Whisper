//
//  ContentView.swift
//  audioToText
//
//  Created by marvel on 2023/3/19.
//
import SwiftUI

struct ContentView: View {
    @ObservedObject var fileUploadViewModel = FileUploadViewModel()
    
    var body: some View {
        VStack {
            Button(action: {
                let dialog = NSOpenPanel()
                dialog.title = "Choose a file"
                dialog.showsResizeIndicator = true
                dialog.showsHiddenFiles = false
                dialog.canChooseDirectories = false
                dialog.canChooseFiles = true
                dialog.allowedFileTypes = ["mp4", "mov", "mp3", "wav", "aac", "m4a", "mpeg", "mpga", "wav", "webm"]
                  
                if (dialog.runModal() == NSApplication.ModalResponse.OK) {
                    let result = dialog.url
                    if (result != nil) {
                        self.fileUploadViewModel.uploadFile(url: result!)
                    }
                } else {
                    return
                }
            }) {
                Text("Choose a file")
                    .padding()
                    .foregroundColor(.black)
                    .cornerRadius(10)
            }.frame(height: 55)
            Text("Selected file: \(fileUploadViewModel.fileName)")
            Text("File size: \(fileUploadViewModel.fileSize)")
            
            Text("Transcription")
                                .font(.title)
                                .padding(.top)
            TextEditor(text: $fileUploadViewModel.transcription)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8.0)
                .padding()
            
        }.frame(width: 300,height: 400)
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
