// Feather disable all
/// BSON supports embedded javascript code, this is just a container for it.
///
/// To learn more please see: `https://bsonspec.org/spec.html`
///
/// @param [code=""] The javascript code.

function SnapBSONJSCode(_code = "") constructor
{
    static __BSONType = 0x0D;
    
    code = _code;
    
    static ToBuffer = function(_buffer)
    {
        buffer_write(_buffer, buffer_s32, string_length(code) + 1);
        buffer_write(_buffer, buffer_string, code);
    }
    
    static FromBuffer = function(_buffer)
    {
        buffer_read(_buffer, buffer_s32);
        code = buffer_read(_buffer, buffer_string);
    }
    
    static toString = function()
    {
        return "JSCode: (\"" + code + "\")";
    }
}