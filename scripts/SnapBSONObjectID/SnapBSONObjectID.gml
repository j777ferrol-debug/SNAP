// Feather disable all
/// An ObjectID in the context of BSON is similar to a GUID where it uses some random values
/// and the datetime to create this pseudo-GUID.
///
/// More info: `https://www.mongodb.com/docs/manual/reference/bson-types/#objectid`
///
/// @param [timestamp=date_current_datetime()] The timestamp to initialize the objectID with.

function SnapBSONObjectID(_timestamp = date_current_datetime()) constructor
{
    static _processIDSeed = irandom(549755813887);
    static _objectIDBegin = irandom(8388607);
    
    static __BSONType = 0x07;
    
    timestamp = 0;
    processIDSeed = _processIDSeed;
    objectID = 0;
    
    if (_timestamp != undefined)
    {
        timestamp = floor(date_second_span(date_create_datetime(1970, 1, 1, 0, 0, 0), _timestamp));  // Unix epoch timestamp
        objectID = _objectIDBegin + 1;
    }
    
    static ToBuffer = function(_buffer)
    {
        // The entire format is little-endian EXCEPT for this one datatype? are we kidding right now?
        __SnapToMessagepackLittleEndian(_buffer, buffer_u32, timestamp);
        
        var _i = 4;
        repeat(5)
        {
            var _shift = _i * 8;
            buffer_write(_buffer, buffer_u8, (processIDSeed >> _shift) & 0xFF);
            _i--;
        }
        
        var _i = 2;
        repeat(3)
        {
            var _shift = _i * 8;
            buffer_write(_buffer, buffer_u8, (objectID >> _shift) & 0xFF);
            _i--;
        }
    }
    
    static FromBuffer = function(_buffer)
    {
        // The entire format is little-endian EXCEPT for this one datatype? are we kidding right now?
        timestamp = __SnapFromMessagepackLittleEndian(_buffer, buffer_u32);
        
        processIDSeed = 0;
        var _i = 4;
        repeat(5)
        {
            var _shift = _i * 8;
            processIDSeed |= buffer_read(_buffer, buffer_u8) << _shift;
            _i--;
        }
        
        objectID = 0;
        var _i = 2;
        repeat(3)
        {
            var _shift = _i * 8;
            objectID |= buffer_read(_buffer, buffer_u8) << _shift;
            _i--;
        }
    }
    
    static toString = function()
    {
        
        return "BSONObjectID: (" + date_datetime_string(date_create_datetime(1970, 1, 1, 0, 0, timestamp)) + ", " + string(processIDSeed) + ", " + string(objectID) + ")";
    }
}