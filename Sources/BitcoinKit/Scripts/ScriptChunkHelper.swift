//
//  ScriptChunkHelper.swift
//
//  Copyright © 2018 BitcoinKit developers
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

public enum ScriptChunkError: Error {
    case error(String)
}

public struct ScriptChunkHelper {
    // If encoding is -1, then the most compact will be chosen.
    // Valid values: -1, 0, 1, 2, 4.
    // Returns nil if preferredLengthEncoding can't be used for data, or data is nil or too big.
    public static func scriptData(for data: Data, preferredLengthEncoding: Int) -> Data? {
        var scriptData: Data = Data()

        if data.count < OpCode.OP_PUSHDATA1 && preferredLengthEncoding <= 0 {
            // do nothing
            scriptData += UInt8(data.count)
        } else if data.count <= (0xff) && (preferredLengthEncoding == -1 || preferredLengthEncoding == 1) {
            scriptData += OpCode.OP_PUSHDATA1
            scriptData += UInt8(data.count)
        } else if data.count <= (0xffff) && (preferredLengthEncoding == -1 || preferredLengthEncoding == 2) {
            scriptData += OpCode.OP_PUSHDATA2
            scriptData += UInt16(data.count)
        } else if UInt64(data.count) <= 0xffffffff && (preferredLengthEncoding == -1 || preferredLengthEncoding == 4) {
            scriptData += OpCode.OP_PUSHDATA4
            scriptData += UInt64(data.count)
        } else {
            // Invalid preferredLength encoding or data size is too big.
            return nil
        }
        scriptData += data
        return scriptData
    }

    public static func parseChunk(from scriptData: Data, offset: Int) throws -> ScriptChunk {
        // Data should fit at least one opcode.
        guard scriptData.count > offset else {
            throw ScriptChunkError.error("Parse ScriptChunk failed. Offset is out of range.")
        }

        let opcode: UInt8 = scriptData[offset]

        if opcode > OpCode.OP_PUSHDATA4 {
            // simple opcode
            let range = (offset..<offset + MemoryLayout.size(ofValue: opcode))
            return OpcodeChunk(scriptData: scriptData, range: range)
        } else {
            // push data
            return try parseDataChunk(from: scriptData, offset: offset, opcode: opcode)
        }
    }

    private static func parseDataChunk(from scriptData: Data, offset: Int, opcode: UInt8) throws -> DataChunk {
        // for range
        let count: Int = scriptData.count
//        let chunkLength: Int
        let opCodeSize: Int = MemoryLayout<UInt8>.size
        let dataLengthSize: Int
        let dataSize: Int
        var chunkLength: Int {
            return opCodeSize + dataLengthSize + dataSize
        }

        switch opcode {
        case 0..<OpCode.OP_PUSHDATA1.value:
            dataLengthSize = 0
            dataSize = Int(opcode)
        case OpCode.OP_PUSHDATA1.value:
            dataLengthSize = MemoryLayout<UInt8>.size
            guard offset + opCodeSize + dataLengthSize <= count else {
                throw ScriptChunkError.error("Parse DataChunk failed. OP_PUSHDATA1 error")
            }
            dataSize = scriptData.withUnsafeBytes {
                Int($0.load(fromByteOffset: offset + opCodeSize, as: UInt8.self))
            }
        case OpCode.OP_PUSHDATA2.value:
            dataLengthSize = MemoryLayout<UInt16>.size
            guard offset + opCodeSize + dataLengthSize <= count else {
                throw ScriptChunkError.error("Parse DataChunk failed. OP_PUSHDATA2 error")
            }
            dataSize = scriptData.withUnsafeBytes {
                Int(
                    CFSwapInt16LittleToHost(
                        $0.load(fromByteOffset: offset + opCodeSize, as: UInt16.self)
                    )
                )
            }
        case OpCode.OP_PUSHDATA4.value:
            dataLengthSize = MemoryLayout<UInt32>.size
            guard offset + opCodeSize + dataLengthSize <= count else {
                throw ScriptChunkError.error("Parse DataChunk failed. OP_PUSHDATA4 error")
            }
            dataSize = scriptData.withUnsafeBytes {
                Int(
                    CFSwapInt32LittleToHost(
                        $0.load(fromByteOffset: offset + opCodeSize, as: UInt32.self)
                    )
                )
            }
        default:
            // cannot happen because it's opcode
            throw ScriptChunkError.error("Parse DataChunk failed. OP_CODE: \(opcode).")
        }

        guard offset + chunkLength <= count else {
            throw ScriptChunkError.error("Parse DataChunk failed. Push data is out of bounds error.")
        }
        let range = (offset..<offset + chunkLength)
        return DataChunk(scriptData: scriptData, range: range)
    }
}
