// Feather disable all
/// BSON is a binary version of JSON popularised by MongoDB, it is a widely used format for interchanging data
/// across networks due to it being fast and somewhat efficient.
///
/// BSON spec:   `https://bsonspec.org/spec.html`
/// BSON tester: `https://mcraiha.github.io/tools/BSONhexToJSON/bsonfiletojson.html`
/// 
/// @return Buffer that contains binary encoded struct/array nested data, using Binary JSON
/// 
/// @param buffer                      Buffer to write data to
/// @param struct/array                The data to be encoded. Can contain structs, arrays, strings, and numbers.   N.B. Will not encode ds_list, ds_map etc.
/// @param [alphabetizeStructs=false]  Whether to alphabetize struct variable names. Incurs a performance penalty is set to <true>

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

function SnapBufferWriteBSON(_buffer, _value, _alphabetizeStructs = false)
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
    
    // Set up some tracking here
    __SnapBSON().__currentDocumentLevel = -1;
    __SnapBSON().__documentStartOffsets = [  ];
    
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
        }
        
        return __SnapBufferWriteBSON(_buffer, undefined, _value, _alphabetizeStructs);
    }
}

//We have to use this weird workaround because you can't static_get() a function you haven't run before
function __SnapBufferWriteBSONStructIteratorMethod()
{
    static _method = method(
        {
            __buffer: undefined,
            __alphabetizeStructs: false,
        },
        function(_name, _value)
        {
            if (!is_string(_name)) show_error("SNAP:\nKeys must be strings\n ", true);
            
            __SnapBufferWriteBSON(__buffer, _name, _value, __alphabetizeStructs);
        }
    );
    
    return _method;
}

function __SnapBufferWriteBSON(_buffer, _name, _value, _alphabetizeStructs)
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
        var _struct = _value;
        var _count = variable_struct_names_count(_struct);
        
        // We only write the type if we are not at the root document        
        if (_name != undefined)
        {
            buffer_write(_buffer, buffer_u8, 0x03); //Struct / document
            buffer_write(_buffer, buffer_string, _name);
        }
        
        // Tracking
        array_push(__SnapBSON().__documentStartOffsets, buffer_tell(_buffer));
        __SnapBSON().__currentDocumentLevel++;
        
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
                    
                    __SnapBufferWriteBSON(_buffer, _varName, _struct[$ _varName], _alphabetizeStructs);
                
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
        var _startOffset = __SnapBSON().__documentStartOffsets[__SnapBSON().__currentDocumentLevel];
        var _endOffset = buffer_tell(_buffer);
        buffer_poke(_buffer, _startOffset, buffer_s32, _endOffset - _startOffset);
        
        array_pop(__SnapBSON().__documentStartOffsets);
        __SnapBSON().__currentDocumentLevel--;
    }
    else if (is_array(_value))
    {
        var _array = _value;
        var _count = array_length(_array);
        
        buffer_write(_buffer, buffer_u8, 0x04); ///Array
        buffer_write(_buffer, buffer_string, _name);
        
        // Tracking
        array_push(__SnapBSON().__documentStartOffsets, buffer_tell(_buffer));
        __SnapBSON().__currentDocumentLevel++;
        
        buffer_write(_buffer, buffer_s32, 0);
        
        var _i = 0;
        repeat(_count)
        {
            // BSON stores arrays as if it's a struct with each index being a struct variable.
            // Example: `{ "0": "Hello World!", "1": 98174, "2": "Why does it do this?" }`.
            __SnapBufferWriteBSON(_buffer, _i, _array[_i], _alphabetizeStructs);
            ++_i;
        }
        
        // Terminate document
        buffer_write(_buffer, buffer_u8, 0);
        
        // Tracking
        var _startOffset = __SnapBSON().__documentStartOffsets[__SnapBSON().__currentDocumentLevel];
        var _endOffset = buffer_tell(_buffer);
        buffer_poke(_buffer, _startOffset, buffer_s32, _endOffset - _startOffset);
        
        array_pop(__SnapBSON().__documentStartOffsets);
        __SnapBSON().__currentDocumentLevel--;
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
            buffer_write(_buffer, buffer_u8, 128 + buffer_get_type(_value)); // 128+ are user-definable, so we can make use by saving the buffer type
            
            buffer_copy(_value, 0, _bufferSize, _buffer, buffer_tell(_buffer));
            buffer_seek(_buffer, buffer_seek_relative, _bufferSize);
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
        
        // Tracking
        array_push(__SnapBSON().__documentStartOffsets, buffer_tell(_buffer));
        __SnapBSON().__currentDocumentLevel++;
        
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
        var _startOffset = __SnapBSON().__documentStartOffsets[__SnapBSON().__currentDocumentLevel];
        var _endOffset = buffer_tell(_buffer);
        buffer_poke(_buffer, _startOffset, buffer_s32, _endOffset - _startOffset);
        
        array_pop(__SnapBSON().__documentStartOffsets);
        __SnapBSON().__currentDocumentLevel--;
    }
    else if (is_array(_value))
    {
        var _array = _value;
        var _count = array_length(_array);
        
        buffer_write(_buffer, buffer_u8, 0x04); ///Array
        buffer_write(_buffer, buffer_string, _name);
        
        // Tracking
        array_push(__SnapBSON().__documentStartOffsets, buffer_tell(_buffer));
        __SnapBSON().__currentDocumentLevel++;
        
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
        var _startOffset = __SnapBSON().__documentStartOffsets[__SnapBSON().__currentDocumentLevel];
        var _endOffset = buffer_tell(_buffer);
        buffer_poke(_buffer, _startOffset, buffer_s32, _endOffset - _startOffset);
        
        array_pop(__SnapBSON().__documentStartOffsets);
        __SnapBSON().__currentDocumentLevel--;
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