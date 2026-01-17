// Feather disable all
/// A UTC datetime based on the unix epoch in milliseconds.
///
/// @param [timestamp=date_current_datetime()] The GameMaker timestamp to initialize the UTC datetime with.

function SnapBSONUTCDateTime(_timestamp = date_current_datetime()) constructor
{
    static __BSONType = 0x09;
    
    timestamp = 0;
    if (_timestamp != undefined)
    {
        timestamp = _timestamp;
    }
    
    static ToBuffer = function(_buffer)
    {
        // UTC timestamp is stored in milliseconds for some reason
        buffer_write(_buffer, buffer_u64, floor(date_second_span(date_create_datetime(1970, 1, 1, 0, 0, 0), timestamp) * 1000));
    }
    
    static FromBuffer = function(_buffer)
    {
        // UTC timestamp is stored in milliseconds for some reason
        timestamp = date_create_datetime(1970, 1, 1, 0, 0, floor(buffer_read(_buffer, buffer_u64) / 1000));
    }
    
    static toString = function()
    {
        return "UTC Datetime: (" + date_datetime_string(timestamp) + ")";
    }
}