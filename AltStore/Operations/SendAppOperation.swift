//
//  SendAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Network

import AltKit

@objc(SendAppOperation)
class SendAppOperation: ResultOperation<ServerConnection>
{
    let context: AppOperationContext
    
    private let dispatchQueue = DispatchQueue(label: "com.altstore.SendAppOperation")
    
    private var serverConnection: ServerConnection?
    
    init(context: AppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let app = self.context.app, let server = self.context.group.server else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        // self.context.resignedApp.fileURL points to the app bundle, but we want the .ipa.
        let fileURL = InstalledApp.refreshedIPAURL(for: app)
        
        // Connect to server.
        ServerManager.shared.connect(to: server) { (result) in
            switch result
            {
            case .failure(let error): self.finish(.failure(error))
            case .success(let serverConnection):
                self.serverConnection = serverConnection
                
                // Send app to server.
                self.sendApp(at: fileURL, via: serverConnection) { (result) in
                    switch result
                    {
                    case .failure(let error): self.finish(.failure(error))
                    case .success:
                        self.progress.completedUnitCount += 1
                        self.finish(.success(serverConnection))
                    }
                }
            }
        }
    }
}

private extension SendAppOperation
{
    func sendApp(at fileURL: URL, via connection: ServerConnection, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        do
        {
            guard let appData = try? Data(contentsOf: fileURL) else { throw OperationError.invalidApp }
            guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { throw OperationError.unknownUDID }
            
            let request = PrepareAppRequest(udid: udid, contentSize: appData.count)
            
            print("Sending request \(request)")
            connection.send(request) { (result) in
                switch result
                {
                case .failure(let error): completionHandler(.failure(error))
                case .success:
                    
                    print("Sending app data (\(appData.count) bytes)")
                    connection.send(appData, prependSize: false) { (result) in
                        switch result
                        {
                        case .failure(let error): completionHandler(.failure(error))
                        case .success: completionHandler(.success(()))
                        }
                    }
                }
            }
        }
        catch
        {
            completionHandler(.failure(error))
        }
    }
}
