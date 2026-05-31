import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Bandwidth_Monitor")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Unable to load local store: \(error.localizedDescription)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func insertUsage(_ apps: [AppBandwidth]) {
        let context = container.newBackgroundContext()
        context.performAndWait {
            let bucket = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            for app in apps where app.sampledDownloadBytes > 0 || app.sampledUploadBytes > 0 || app.downloadBps > 0 || app.uploadBps > 0 {
                let usage = NSManagedObject(entity: NSEntityDescription.entity(forEntityName: "UsageBucket", in: context)!, insertInto: context)
                usage.setValue(UUID(), forKey: "id")
                usage.setValue(bucket, forKey: "bucketStart")
                usage.setValue(app.id, forKey: "appIdentifier")
                usage.setValue(app.displayName, forKey: "displayName")
                usage.setValue(app.processName, forKey: "processName")
                usage.setValue(Int64(app.pid), forKey: "pid")
                let bytesIn = app.sampledDownloadBytes > 0 ? app.sampledDownloadBytes : Int64(app.downloadBps.rounded())
                let bytesOut = app.sampledUploadBytes > 0 ? app.sampledUploadBytes : Int64(app.uploadBps.rounded())
                usage.setValue(bytesIn, forKey: "bytesIn")
                usage.setValue(bytesOut, forKey: "bytesOut")
            }
            try? context.save()
        }
    }

    func usageTotals(since date: Date) -> (bytesIn: Int64, bytesOut: Int64) {
        let context = container.viewContext
        let request = NSFetchRequest<NSDictionary>(entityName: "UsageBucket")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "bucketStart >= %@", date as NSDate)

        let inExpression = NSExpressionDescription()
        inExpression.name = "bytesInTotal"
        inExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "bytesIn")])
        inExpression.expressionResultType = .integer64AttributeType

        let outExpression = NSExpressionDescription()
        outExpression.name = "bytesOutTotal"
        outExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "bytesOut")])
        outExpression.expressionResultType = .integer64AttributeType

        request.propertiesToFetch = [inExpression, outExpression]
        let result = try? context.fetch(request).first
        return (
            result?["bytesInTotal"] as? Int64 ?? 0,
            result?["bytesOutTotal"] as? Int64 ?? 0
        )
    }

    func usageTotalsByApp(since date: Date) -> [String: (bytesIn: Int64, bytesOut: Int64)] {
        let request = NSFetchRequest<NSDictionary>(entityName: "UsageBucket")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "bucketStart >= %@", date as NSDate)
        request.propertiesToGroupBy = ["appIdentifier"]

        let appExpression = NSExpressionDescription()
        appExpression.name = "appIdentifier"
        appExpression.expression = NSExpression(forKeyPath: "appIdentifier")
        appExpression.expressionResultType = .stringAttributeType

        let inExpression = NSExpressionDescription()
        inExpression.name = "bytesInTotal"
        inExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "bytesIn")])
        inExpression.expressionResultType = .integer64AttributeType

        let outExpression = NSExpressionDescription()
        outExpression.name = "bytesOutTotal"
        outExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "bytesOut")])
        outExpression.expressionResultType = .integer64AttributeType

        request.propertiesToFetch = [appExpression, inExpression, outExpression]
        let rows = (try? container.viewContext.fetch(request)) ?? []
        var totals: [String: (bytesIn: Int64, bytesOut: Int64)] = [:]
        for row in rows {
            guard let appIdentifier = row["appIdentifier"] as? String else { continue }
            totals[appIdentifier] = (
                row["bytesInTotal"] as? Int64 ?? 0,
                row["bytesOutTotal"] as? Int64 ?? 0
            )
        }
        return totals
    }

    func usageApps(since date: Date) -> [AppBandwidth] {
        let request = NSFetchRequest<NSDictionary>(entityName: "UsageBucket")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "bucketStart >= %@", date as NSDate)
        request.propertiesToGroupBy = ["appIdentifier", "displayName", "processName"]

        let appExpression = NSExpressionDescription()
        appExpression.name = "appIdentifier"
        appExpression.expression = NSExpression(forKeyPath: "appIdentifier")
        appExpression.expressionResultType = .stringAttributeType

        let displayNameExpression = NSExpressionDescription()
        displayNameExpression.name = "displayName"
        displayNameExpression.expression = NSExpression(forKeyPath: "displayName")
        displayNameExpression.expressionResultType = .stringAttributeType

        let processNameExpression = NSExpressionDescription()
        processNameExpression.name = "processName"
        processNameExpression.expression = NSExpression(forKeyPath: "processName")
        processNameExpression.expressionResultType = .stringAttributeType

        let inExpression = NSExpressionDescription()
        inExpression.name = "bytesInTotal"
        inExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "bytesIn")])
        inExpression.expressionResultType = .integer64AttributeType

        let outExpression = NSExpressionDescription()
        outExpression.name = "bytesOutTotal"
        outExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "bytesOut")])
        outExpression.expressionResultType = .integer64AttributeType

        request.propertiesToFetch = [
            appExpression,
            displayNameExpression,
            processNameExpression,
            inExpression,
            outExpression
        ]

        let rows = (try? container.viewContext.fetch(request)) ?? []
        return rows.compactMap { row in
            guard let appIdentifier = row["appIdentifier"] as? String else { return nil }
            return AppBandwidth(
                id: appIdentifier,
                displayName: row["displayName"] as? String ?? appIdentifier,
                processName: row["processName"] as? String ?? appIdentifier,
                pid: 0,
                downloadBps: 0,
                uploadBps: 0,
                download24h: row["bytesInTotal"] as? Int64 ?? 0,
                upload24h: row["bytesOutTotal"] as? Int64 ?? 0,
                isActive: false
            )
        }
    }

    func pruneUsage(olderThan date: Date) {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "UsageBucket")
        request.predicate = NSPredicate(format: "bucketStart < %@", date as NSDate)
        _ = try? container.viewContext.execute(NSBatchDeleteRequest(fetchRequest: request))
        try? container.viewContext.save()
    }

    func clearUsage() {
        let request = NSBatchDeleteRequest(fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: "UsageBucket"))
        _ = try? container.viewContext.execute(request)
        try? container.viewContext.save()
    }

    func fetchSpeedTests() -> [SpeedTestResult] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SpeedTestRecord")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        let records = (try? container.viewContext.fetch(request)) ?? []
        return records.compactMap { record in
            guard let id = record.value(forKey: "id") as? UUID,
                  let timestamp = record.value(forKey: "timestamp") as? Date else {
                return nil
            }
            return SpeedTestResult(
                id: id,
                timestamp: timestamp,
                downloadMbps: record.value(forKey: "downloadMbps") as? Double ?? 0,
                uploadMbps: record.value(forKey: "uploadMbps") as? Double ?? 0,
                latencyMs: record.value(forKey: "latencyMs") as? Double ?? 0,
                jitterMs: record.value(forKey: "jitterMs") as? Double ?? 0,
                packetLoss: record.value(forKey: "packetLoss") as? Double,
                serverName: record.value(forKey: "serverName") as? String ?? "Unknown server",
                isp: record.value(forKey: "isp") as? String ?? "Unknown ISP",
                resultURL: record.value(forKey: "resultURL") as? String
            )
        }
    }

    func insertSpeedTest(_ result: SpeedTestResult) {
        let context = container.viewContext
        let record = NSManagedObject(entity: NSEntityDescription.entity(forEntityName: "SpeedTestRecord", in: context)!, insertInto: context)
        record.setValue(result.id, forKey: "id")
        record.setValue(result.timestamp, forKey: "timestamp")
        record.setValue(result.downloadMbps, forKey: "downloadMbps")
        record.setValue(result.uploadMbps, forKey: "uploadMbps")
        record.setValue(result.latencyMs, forKey: "latencyMs")
        record.setValue(result.jitterMs, forKey: "jitterMs")
        record.setValue(result.packetLoss, forKey: "packetLoss")
        record.setValue(result.serverName, forKey: "serverName")
        record.setValue(result.isp, forKey: "isp")
        record.setValue(result.resultURL, forKey: "resultURL")
        try? context.save()
    }

    func clearSpeedTests() {
        let request = NSBatchDeleteRequest(fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: "SpeedTestRecord"))
        _ = try? container.viewContext.execute(request)
        try? container.viewContext.save()
    }
}
