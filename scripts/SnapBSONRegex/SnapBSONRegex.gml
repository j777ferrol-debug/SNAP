// Feather disable all
/// BSON regex has both a pattern and options strings.
///
/// To learn more please see: `https://bsonspec.org/spec.html`
///
/// @param [pattern=""] The regex pattern.
/// @param [options=""] The regex options.

function SnapBSONRegex(_pattern = "", _options = "") constructor
{
    static __BSONType = 0x0B;
    
    pattern = _pattern;
    options = _options;
    
    static ToBuffer = function(_buffer)
    {
        buffer_write(_buffer, buffer_string, pattern);
        buffer_write(_buffer, buffer_string, options);
    }
    
    static FromBuffer = function(_buffer)
    {
        pattern = buffer_read(_buffer, buffer_string);
        options = buffer_read(_buffer, buffer_string);
    }
    
    static toString = function()
    {
        return "Regex: (\"" + pattern + "\", \"" + options + "\")";
    }
}