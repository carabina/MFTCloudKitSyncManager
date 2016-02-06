//
//  NSManagedObject+GSSUtilities.swift
//  CloudKitDemo
//
//  Created by Christian Gossain on 2015-11-08.
//  Copyright © 2015 Christian Gossain. All rights reserved.
//

import Foundation
import CoreData
import CloudKit

struct GSSReference {
    /// The name of the entity being referenced
    let destinationEntityName: String
    
    /// The CKReference object that points to the destination entity
    let reference: CKReference
}

extension NSManagedObject {
    
    public func gss_modificationDate() -> NSDate {
        return self.valueForKeyPath(GSSLocalRecordModificationDateAttributeName) as! NSDate
    }
    
    /**
     Returns a CKRecord counterpart to this object by either creating a new one or if the managed object is already storing the encoded fields of a CKRecord, simply updates that record and returns it.
     */
    func toCKRecord() -> CKRecord {
        var record: CKRecord?
        
        if let encodedSystemFields = self.valueForKey(GSSLocalRecordEncodedSystemFieldsAttributeName) as? NSData {
            // an encoded CKRecord is associated with this object; unarchive it and update it
            let unarchiver = NSKeyedUnarchiver(forReadingWithData: encodedSystemFields)
            unarchiver.requiresSecureCoding = true
            
            // this is the bare bones record containing only system fields; populate with the rest of the data
            record = CKRecord(coder: unarchiver)
        }
        else {
            // there is no encoded CKRecord; create a new one
            let recordID = self.toCKRecordID()
            
            record = CKRecord(recordType: self.entity.name!, recordID: recordID)
        }
        
        // populate the record with the values of self
        for property in self.entity.properties {
            if let attribute = property as? NSAttributeDescription {
                record?.setValue(self.valueForKey(attribute.name), forKey: attribute.name)
            }
            else if let relationship = property as? NSRelationshipDescription where !relationship.toMany {
                // only suporting to-one relationships at the moment (don't have a need for many-to-many at this point)
                // many-to-many is also may mean that your data model needs re-thinking to avoid them
                
                // get the destination object
                if let destinationObject = self.valueForKey(relationship.name) {
                    // create a CKRecordID that points to this object
                    let recordID = destinationObject.toCKRecordID()
                    var action = CKReferenceAction.DeleteSelf // default if there is no inverse relationship
                    
                    if let inverse = relationship.inverseRelationship {
                        // if there is an inverse relationship, determine the action according to the delete rule
                        switch inverse.deleteRule {
                        case .CascadeDeleteRule:
                            action = .DeleteSelf
                        default:
                            action = .None
                        }
                    }
                    
                    let reference = CKReference(recordID: recordID, action: action)
                    record?.setValue(reference, forKey: relationship.name)
                }
            }
        }
        return record!
    }
    
    func toCKRecordID() -> CKRecordID {
        let localRecordID = self.valueForKey(GSSLocalRecordIDAttributeName) as! String
        let zoneID = CKRecordZoneID(zoneName: GSSCloudKitSyncManagerZoneName, ownerName: CKOwnerDefaultName)
        let recordID = CKRecordID(recordName: localRecordID, zoneID: zoneID)
        
        return recordID
    }
    
    /** 
     Update the attributes of the receiver with the contents of the CKRecord, and returns a dictionary containing key value pair of the availble relationship/references
     */
    func updateAttributesWithCKRecord(record: CKRecord) -> [String : GSSReference] {
        var references = [String : GSSReference]()
        
        // populate self with the values of the record
        for key in record.allKeys() {
            if let attribute = self.entity.attributesByName[key] {
                self.setValue(record.valueForKey(key), forKey: attribute.name)
            }
            else if let relationship = self.entity.relationshipsByName[key] where !relationship.toMany {
                if let reference = record.valueForKey(relationship.name) as? CKReference {
                    let destinationEntityName = (relationship.destinationEntity?.name)!
                    references[key] = GSSReference(destinationEntityName: destinationEntityName, reference: reference)
                }
            }
        }
        
        // encode the records system fields to be stored in the objects as data
        let mutableData = NSMutableData()
        let archiver = NSKeyedArchiver(forWritingWithMutableData: mutableData)
        archiver.requiresSecureCoding = true
        record.encodeSystemFieldsWithCoder(archiver)
        archiver.finishEncoding()
        
        // encode the system fields
        self.setValue(mutableData, forKey: GSSLocalRecordEncodedSystemFieldsAttributeName)
        
        // return a dictionary containing the GSSReference associated with the objects relationships
        return references
    }
}