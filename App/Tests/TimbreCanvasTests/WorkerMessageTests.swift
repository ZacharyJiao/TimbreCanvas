import Foundation
import Testing
@testable import TimbreCanvas

@Test func workerCommandUsesStableJSONKeys() throws {
    let command = WorkerCommand(
        name: "load_model",
        requestID: "request-1",
        payload: ["engineID": .string("indextts2"), "memoryLimitGB": .number(24)]
    )

    let data = try WorkerJSONCodec.encode(command)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["command"] as? String == "load_model")
    #expect(object["requestID"] as? String == "request-1")
    #expect((object["payload"] as? [String: Any])?["engineID"] as? String == "indextts2")
}

@Test func readyAndErrorResponsesDecodeWithoutLosingRequestID() throws {
    let ready = try WorkerJSONCodec.decode(
        Data(#"{"type":"ready","requestID":"r1","engineID":"indextts2"}"#.utf8)
    )
    let error = try WorkerJSONCodec.decode(
        Data(#"{"type":"error","requestID":"r2","code":"invalid_output","message":"无法写入"}"#.utf8)
    )

    #expect(ready == .ready(requestID: "r1", engineID: "indextts2"))
    #expect(error == .error(.init(requestID: "r2", code: "invalid_output", message: "无法写入")))
}

@Test func lineBufferKeepsIncompleteJSONForNextRead() {
    var buffer = JSONLineBuffer()

    let first = buffer.append(Data("{\"type\":\"result\"}\n{\"type\"".utf8))
    let second = buffer.append(Data(":\"progress\"}\n".utf8))

    #expect(first == [#"{"type":"result"}"#])
    #expect(second == [#"{"type":"progress"}"#])
}

