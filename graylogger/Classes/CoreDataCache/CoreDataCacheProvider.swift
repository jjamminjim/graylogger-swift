//
//  CoreDataCacheProvider.swift
//  graylogger
//
//  Created by Jim Boyd on 7/3/17.
//

import Foundation
import CoreData
import DBC
import SwiftyJSON

public class CoreDataCacheProvider:  CacheProvider {
	public enum StoreType {
		case sqlite
		case inMemory
		
		var pscType: String
		{
			switch self
			{
			case .sqlite: return NSSQLiteStoreType
			case .inMemory: return NSInMemoryStoreType
			}
		}
	}
	
	let dbBundle:Bundle
	let storeType:StoreType

	public init(storeType:StoreType = .sqlite, bundle:Bundle = Bundle.main) {
		self.storeType = storeType
		self.dbBundle = bundle
	}
	
	private lazy var cacheDirectory: URL = {
        if let cachesDirectory = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor:nil, create:false) {
            var cachesDirectoryPath = cachesDirectory.appendingPathComponent(self.dbBundle.bundleId)
			var isDir : ObjCBool = false

			if !FileManager.default.fileExists(atPath: cachesDirectoryPath.absoluteString, isDirectory: &isDir) {
				do {
					try FileManager.default.createDirectory(at: cachesDirectoryPath, withIntermediateDirectories: true, attributes: nil)
				}
				catch {
					print("Error trying to create file path : \(error)")
				}
			}
			return cachesDirectoryPath
        }
        return URL(fileURLWithPath: "")
	}()
	
	private lazy var managedObjectModel: NSManagedObjectModel = {
		let bundle = Bundle(for: CoreDataCacheProvider.self)
		return NSManagedObjectModel.mergedModel(from: [bundle])!
	}()
	
	private lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
		let psc =  NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
		
		var storeURL: URL? = self.cacheDirectory.appendingPathComponent("CoreDataCacheProvider.sqlite")
		do {
			_ = try psc.addPersistentStore(ofType: self.storeType.pscType, configurationName: nil, at: storeURL, options: nil)
		}
		catch {
            requireFailure("[CoreDataCacheProvider] Error \(error)")
		}
		
		return psc
	}()
	
	public lazy var managedObjectContext: NSManagedObjectContext = {
		let moc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		moc.persistentStoreCoordinator = self.persistentStoreCoordinator
		
		return moc
	}()
	
	public var hasCache: Bool {
		return self.count() > 0
	}
	
	public func cacheLog(endpoint: GraylogEndpoint, payload jsonData: Data) {
		self.managedObjectContext.perform {
			let cachedObject:CachedLog = NSEntityDescription.insertNewObject(forEntityName: "CachedLog", into: self.managedObjectContext) as! CachedLog
			
			cachedObject.type = endpoint.logType.rawValue
			cachedObject.host = endpoint.host
			cachedObject.port = endpoint.port as NSNumber
			cachedObject.payload = jsonData as NSData
			
			do {
				try self.managedObjectContext.save()
			}
			catch {
				requireFailure("Could not create/save log cache : /(error)")
			}
		}
	}
	
	public func flushCache(submitCacheItem: @escaping (GraylogEndpoint, Data, @escaping (Bool) -> Void) -> Void) {
		
		self.managedObjectContext.perform {
			let fetchRequest:NSFetchRequest<CachedLog> = CachedLog.fetchRequest()
			var cacheItems = [CachedLog]()
			
			fetchRequest.entity = NSEntityDescription.entity(forEntityName: "CachedLog", in: self.managedObjectContext)
			fetchRequest.includesPropertyValues = true
			
			do {
				cacheItems = try self.managedObjectContext.fetch(fetchRequest)
			}
			catch {
				print("[CABOGeocoderCache] Error occured getting all objects in core data store. \(error)")
			}
			
			for cache in cacheItems {
				guard let type = cache.type,
					let logType = GraylogType(rawValue: type),
					let host = cache.host,
					let port = cache.port,
					let payload = cache.payload as Data? else {
						requireFailure("Could not load log values for cached object")
						return
					}
				
				let endpoint = GraylogEndpoint(logType: logType, host: host, port: port.intValue)
				
				submitCacheItem(endpoint, payload) { (_ didSubmit:Bool) -> Void in
					// Remove the item if it was submitted.
					if didSubmit {
						self.managedObjectContext.perform {
							self.managedObjectContext.delete(cache)
							
							do {
								try self.managedObjectContext.save()
							}
							catch {
								requireFailure("Could not delete log cache : /(error)")
							}
							
						}
					}
				}
			}
		}
		
	}
}

fileprivate extension CoreDataCacheProvider {
	func count() -> Int {
		var result = 0
		
		self.managedObjectContext.performAndWait {
			let fetchRequest:NSFetchRequest<CachedLog> = CachedLog.fetchRequest()
			
			fetchRequest.entity = NSEntityDescription.entity(forEntityName: "CachedLog", in: self.managedObjectContext)
			fetchRequest.includesPropertyValues = false
			
			do {
				result = try self.managedObjectContext.count(for: fetchRequest)
			}
			catch {
				print("[CABOGeocoderCache] Error occured getting all objects in core data store. \(error)")
			}
		}
		
		return result
	}
}
