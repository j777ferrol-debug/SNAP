// Feather disable all
/// BSON is a binary version of JSON popularised by MongoDB, it is a widely used format for interchanging data
/// across networks due to it being fast and somewhat efficient.
///
///	Unsupported non-deprecated types: objectID, UTCdatetime, null, uint64, regex, JScode, float128, min key, max key.
/// LTS does not support writing binary blobs.
///
/// BSON spec:   `https://bsonspec.org/spec.html`
/// BSON tester: `https://mcraiha.github.io/tools/BSONhexToJSON/bsonfiletojson.html`
/// 
/// @return Buffer that contains binary encoded struct/array nested data, using Binary JSON
/// 
/// @param buffer                      Buffer to write data to
/// @param struct/array                The data to be encoded. Can contain structs, arrays, strings, and numbers.   N.B. Will not encode ds_list, ds_map etc.
/// @param [alphabetizeStructs=false]  Whether to alphabetize struct variable names. Incurs a performance penalty is set to <true>
/// @param [binaryBlobType=undefined]  The binary blob type to use, leave as `undefined` to encode the buffer_type as 128-131. See `subtype` in the spec for more information

/*
    0x00  -  EOO (end of object)
    0x01  -  double
    0x02  -  string
    0x03  -  document (struct)
    0x04  -  array (encoded as a document)
    0x05  -  binary blob
    0x06  -  <undefined>
    0x07  -  object ID
    0x08  -  boolean
    0x09  -  UTCdatetime
    0x0A  -  <null>
    0x10  -  int32
	0x11  -  uint64
	0x12  -  int64
*/

function SnapBufferWriteBSON(_buffer, _value, _alphabetizeStructs = false, _binaryBlobType = undefined)
{
    // BSON must have a document as the first element type, we make no assumsions here or change
    // how the data looks, so we just error out instead.
    if (not is_struct(_value))
    {
        show_error("SNAP:\nBSON root container must be a document/struct\n ", true);
    }

    //Determine if we need to use the legacy codebase by checking against struct_foreach()
    static _useLegacy = undefined;
    if (_useLegacy == undefined)
    {
        try
        {
            struct_foreach({}, function() {});
            _useLegacy = false;
        }
        catch(_error)
        {
            _useLegacy = true;
        }
    }
    
    if (_useLegacy)
    {
        return __SnapBufferWriteBSONLegacy(_buffer, undefined, _value, _alphabetizeStructs);
    }
    else
    {
        with(method_get_self(__SnapBufferWriteBSONStructIteratorMethod()))
        {
            __buffer = _buffer;
            __alphabetizeStructs = _alphabetizeStructs;
			__binaryBlobType = _binaryBlobType;
        }
        
        return __SnapBufferWriteBSON(_buffer, undefined, _value, _alphabetizeStructs, _binaryBlobType);
    }
}

//We have to use this weird workaround because you can't static_get() a function you haven't run before
function __SnapBufferWriteBSONStructIteratorMethod()
{
    static _method = method(
        {
            __buffer: undefined,
            __alphabetizeStructs: false,
			__binaryBlobType: undefined,
        },
        function(_name, _value)
        {
            if (!is_string(_name)) show_error("SNAP:\nKeys must be strings\n ", true);
            
            __SnapBufferWriteBSON(__buffer, _name, _value, __alphabetizeStructs, __binaryBlobType);
        }
    );
    
    return _method;
}

function __SnapBufferWriteBSON(_buffer, _name, _value, _alphabetizeStructs, _binaryBlobType)
{
    static _structIteratorMethod = __SnapBufferWriteBSONStructIteratorMethod();
    
    if (is_method(_value)) //Implicitly also a struct so we have to check this first
    {
        buffer_write(_buffer, buffer_u8, 0x02); //Convert all methods to strings
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_s32, string_length(string(_value)) + 1) // Non-cstring type string, includes size of string + the final terminater byte
        buffer_write(_buffer, buffer_string, string(_value));
    }
    else if (is_struct(_value))
    {
        // Before we write the struct let's check for any extended types
        if (variable_struct_exists(_value, "__BSONType"))
        {
            buffer_write(_buffer, buffer_u8, _value[$ "__BSONType"]);
            buffer_write(_buffer, buffer_string, _name);
            _value.ToBuffer(_buffer);
        }
        else
        {
            var _struct = _value;
            var _count = variable_struct_names_count(_struct);
        
            // We only write the type if we are not at the root document        
            if (_name != undefined)
            {
                buffer_write(_buffer, buffer_u8, 0x03); //Struct / document
                buffer_write(_buffer, buffer_string, _name);
            }
        
            // Starting offset
            var _startingOffset = buffer_tell(_buffer);
        
            // Size placeholder
            buffer_write(_buffer, buffer_s32, 0);
        
            if (_count > 0)
            {
                if (_alphabetizeStructs)
                {
                    var _names = variable_struct_get_names(_struct);
                    array_sort(_names, true);
                    var _i = 0;
                    repeat(_count)
                    {
                        var _varName = _names[_i];
                        if (!is_string(_varName)) show_error("SNAP:\nKeys must be strings\n ", true);
                    
                        __SnapBufferWriteBSON(_buffer, _varName, _struct[$ _varName], _alphabetizeStructs, _binaryBlobType);
                
                        ++_i;
                    }
                }
                else
                {
                    struct_foreach(_struct, _structIteratorMethod);
                }
            }
        
            // Terminate document
            buffer_write(_buffer, buffer_u8, 0x00);
        
            // Tracking
            var _endingOffset = buffer_tell(_buffer);
            buffer_poke(_buffer, _startingOffset, buffer_s32, _endingOffset - _startingOffset);
        }
    }
    else if (is_array(_value))
    {
        var _array = _value;
        var _count = array_length(_array);
        
        buffer_write(_buffer, buffer_u8, 0x04); ///Array
        buffer_write(_buffer, buffer_string, _name);
        
        // Starting offset
        var _startingOffset = buffer_tell(_buffer);
        
        buffer_write(_buffer, buffer_s32, 0);
        
        var _i = 0;
        repeat(_count)
        {
            // BSON stores arrays as if it's a struct with each index being a struct variable.
            // Example: `{ "0": "Hello World!", "1": 98174, "2": "Why does it do this?" }`.
            __SnapBufferWriteBSON(_buffer, _i, _array[_i], _alphabetizeStructs, _binaryBlobType);
            ++_i;
        }
        
        // Terminate document
        buffer_write(_buffer, buffer_u8, 0);
        
        // Tracking
        var _endingOffset = buffer_tell(_buffer);
        buffer_poke(_buffer, _startingOffset, buffer_s32, _endingOffset - _startingOffset);
    }
    else if (is_string(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x02); //String
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_s32, string_length(_value) + 1) // Non-cstring type string, includes size of string + the final terminater byte
        buffer_write(_buffer, buffer_string, _value);
    }
    else if (is_real(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x01); //f64
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_f64, _value);
    }
    else if (is_bool(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x08); //boolean
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_u8, _value ? 0x01 : 0x00);
    }
    else if (is_undefined(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x06); //<undefined>
        buffer_write(_buffer, buffer_string, _name);
		show_debug_message("SnapBSON: Undefined is a deprecated type, please avoid use");
    }
    else if (is_int32(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x10); //s32
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_s32, _value);
    }
    else if (is_int64(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x12); //u64
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_u64, _value);
    }
    else if (is_handle(_value))
    {
        if (buffer_exists(_value))
        {
            buffer_write(_buffer, buffer_u8, 0x05); //binary blob
            buffer_write(_buffer, buffer_string, _name);
            
            var _bufferSize = buffer_get_size(_value);
            if (_bufferSize > 0x7FFFFFFF) show_error("SNAP:\nBSON blob size cannot exceed the 32-bit signed integer limit. \n", true);
            
	        buffer_write(_buffer, buffer_s32, _bufferSize);
			
			if (_binaryBlobType == undefined)
			{
	            buffer_write(_buffer, buffer_u8, 128 + buffer_get_type(_value)); // 128+ are user-definable, so we can make use by saving the buffer type
			}
			else
			{
                if (_binaryBlobType < 0 or _binaryBlobType > 255)
                {
                    show_error("SNAP:\nBinary blob subtype must be between 0 and 255.\n", true);
                }
                buffer_write(_buffer, buffer_u8, _binaryBlobType);
			}
            
            buffer_copy(_value, 0, _bufferSize, _buffer, buffer_tell(_buffer));
            buffer_seek(_buffer, buffer_seek_relative, _bufferSize);
        }
		else
		{
			show_message("Handle \"" + typeof(_value) + "\" not supported");
		}
    }
    else
    {
        show_message("Datatype \"" + typeof(_value) + "\" not supported");
    }
    
    return _buffer;
}

//Legacy version for LTS use
function __SnapBufferWriteBSONLegacy(_buffer, _name, _value, _alphabetizeStructs)
{
    if (is_method(_value)) //Implicitly also a struct so we have to check this first
    {
        buffer_write(_buffer, buffer_u8, 0x02); //Convert all methods to strings
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_s32, string_length(string(_value)) + 1) // Non-cstring type string, includes size of string + the final terminater byte
        buffer_write(_buffer, buffer_string, string(_value));
    }
    else if (is_struct(_value))
    {
        // Before we write the struct let's check for any extended types
        if (variable_struct_exists(_value, "__BSONType"))
        {
            buffer_write(_buffer, buffer_u8, _value[$ "__BSONType"]);
            buffer_write(_buffer, buffer_string, _name);
            _value.ToBuffer(_buffer);
        }
        else
        {
            var _struct = _value;
        
            var _names = variable_struct_get_names(_struct);
            if (_alphabetizeStructs && is_array(_names)) array_sort(_names, true);
        
            var _count = array_length(_names);
        
            // We only write the type if we are not at the root document        
            if (_name != undefined)
            {
                buffer_write(_buffer, buffer_u8, 0x03); //Struct / document
                buffer_write(_buffer, buffer_string, _name);
            }
        
            // Starting offset
            var _startingOffset = buffer_tell(_buffer);
        
            // Size placeholder
            buffer_write(_buffer, buffer_s32, 0);
        
            var _i = 0;
            repeat(_count)
            {
                var _varName = _names[_i];
                if (!is_string(_varName)) show_error("SNAP:\nKeys must be strings\n ", true);
            
                __SnapBufferWriteBSONLegacy(_buffer, _varName, _struct[$ _varName], _alphabetizeStructs);
            
                ++_i;
            }
        
            // Terminate document
            buffer_write(_buffer, buffer_u8, 0x00);
        
            // Tracking
            var _endingOffset = buffer_tell(_buffer);
            buffer_poke(_buffer, _startingOffset, buffer_s32, _endingOffset - _startingOffset);
        }
    }
    else if (is_array(_value))
    {
        var _array = _value;
        var _count = array_length(_array);
        
        buffer_write(_buffer, buffer_u8, 0x04); ///Array
        buffer_write(_buffer, buffer_string, _name);
        
        // Starting offset
        var _startingOffset = buffer_tell(_buffer);
        
        buffer_write(_buffer, buffer_s32, 0);
        
        var _i = 0;
        repeat(_count)
        {
            // BSON stores arrays as if it's a struct with each index being a struct variable.
            // Example: `{ "0": "Hello World!", "1": 98174, "2": "Why does it do this?" }`.
            __SnapBufferWriteBSONLegacy(_buffer, _i, _array[_i], _alphabetizeStructs);
            ++_i;
        }
        
        // Terminate document
        buffer_write(_buffer, buffer_u8, 0);
        
        // Tracking
        var _endingOffset = buffer_tell(_buffer);
        buffer_poke(_buffer, _startingOffset, buffer_s32, _endingOffset - _startingOffset);
    }
    else if (is_string(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x02); //String
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_s32, string_length(_value) + 1) // Non-cstring type string, includes size of string + the final terminater byte
        buffer_write(_buffer, buffer_string, _value);
    }
    else if (is_real(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x01); //f64
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_f64, _value);
    }
    else if (is_bool(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x08); //boolean
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_u8, _value ? 0x01 : 0x00);
    }
    else if (is_undefined(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x06); //<undefined>
        buffer_write(_buffer, buffer_string, _name);
		show_debug_message("SnapBSON: Undefined is a deprecated type, please avoid use");
    }
    else if (is_int32(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x10); //s32
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_s32, _value);
    }
    else if (is_int64(_value))
    {
        buffer_write(_buffer, buffer_u8, 0x12); //u64
        buffer_write(_buffer, buffer_string, _name);
        buffer_write(_buffer, buffer_u64, _value);
    }
    else
    {
        show_message("Datatype \"" + typeof(_value) + "\" not supported");
    }
    
    return _buffer;
}