// Feather disable all

/// BSON is a binary version of JSON popularised by MongoDB, it is a widely used format for
/// interchanging data across networks due to it being fast and somewhat efficient. This particular
/// BSON reader will not validate the sizes of containers or strings.
///
///	N.B. This function does not support uint64 and float128 types.
///
/// BSON spec:   `https://bsonspec.org/spec.html`
/// BSON tester: `https://mcraiha.github.io/tools/BSONhexToJSON/bsonfiletojson.html`
///
/// @return Nested struct/array data encoded from the buffer, using Binary JSON
/// 
/// @param buffer                           Binary data to be decoded, created by SnapBufferWriteBSON()
/// @param offset                           Start position for binary decoding in the buffer. Defaults to 0, the start of the buffer
/// @param [skipEmbeddedBuffers=true]       Skip past any embedded buffers. Defaults to 0
/// @param [embeddedBufferType=undefined]   Overrides the internal buffer subtype for embedded buffers, see `subtype` in the spec for more information

/*
    0x00  -  EOO (end of object)
    0x01  -  double
    0x02  -  string
    0x03  -  document (struct)
    0x04  -  array (encoded as a document)
    0x05  -  binary blob
    0x06  -  <undefined>        (deprecated)
    0x07  -  object ID
    0x08  -  boolean
    0x09  -  UTCdatetime
    0x0A  -  <null>
    0x0B  -  regex
    0x0C  -  DB pointer         (deprecated)
    0x0D  -  JS code            (unsupported)
    0x0E  -  symbol             (deprecated)
    0x0F  -  JS code with scope (deprecated)
    0x10  -  int32
	0x11  -  uint64             (unsupported)
	0x12  -  int64
    0x13  -  decimal128         (unsupported)
*/

function SnapBufferReadBSON(_buffer, _offset, _skipEmbeddedBuffers = false, _embeddedBufferType = undefined)
{
    var _oldOffset = buffer_tell(_buffer);
    buffer_seek(_buffer, buffer_seek_start, _offset);
    var _value = __SnapFromBSONValue(_buffer, undefined, _skipEmbeddedBuffers, _embeddedBufferType);
    buffer_seek(_buffer, buffer_seek_start, _oldOffset);
    return _value;
}

function __SnapFromBSONValue(_buffer, _container, _skipEmbeddedBuffers, _embeddedBufferType)
{
    var _datatype = 0x03;
    var _name = undefined;
    
    if (_container != undefined)
    {
        _datatype = buffer_read(_buffer, buffer_u8);
        _name = buffer_read(_buffer, buffer_string);
    }
    
    switch(_datatype)
    {
        case 0x03: // struct / document
            buffer_read(_buffer, buffer_s32); // skip past the size of the object
            var _struct = {  };
            var _nextType = buffer_peek(_buffer, buffer_tell(_buffer), buffer_u8);
            
            // Check to make sure that we haven't hit the end of the struct as it's null terminated
            while(_nextType != 0x00)
            {
                __SnapFromBSONValue(_buffer, _struct, _skipEmbeddedBuffers, _embeddedBufferType);
                _nextType = buffer_peek(_buffer, buffer_tell(_buffer), buffer_u8);
            }
            
            buffer_read(_buffer, buffer_u8);
            __SnapBufferReadBSONAddToContainer(_container, _name, _struct);
            
            return _struct;
        break;
        
        case 0x04: // array
            buffer_read(_buffer, buffer_s32); // skip past the size of the object
            var _array = [  ];
            var _nextType = buffer_peek(_buffer, buffer_tell(_buffer), buffer_u8);
            
            // Check to make sure that we haven't hit the end of the array as it's null terminated
            while(_nextType != 0x00)
            {
                __SnapFromBSONValue(_buffer, _array, _skipEmbeddedBuffers, _embeddedBufferType);
                _nextType = buffer_peek(_buffer, buffer_tell(_buffer), buffer_u8);
            }
            
            buffer_read(_buffer, buffer_u8);
            __SnapBufferReadBSONAddToContainer(_container, _name, _array);
            
            return _array;
        break;
        
        case 0x01: // f64
            var _value = buffer_read(_buffer, buffer_f64);
            __SnapBufferReadBSONAddToContainer(_container, _name, _value);
            return _value
        break;
        
        case 0x02: // string
            buffer_read(_buffer, buffer_s32); // Skip past string size
            var _value = buffer_read(_buffer, buffer_string);
            __SnapBufferReadBSONAddToContainer(_container, _name, _value);
            return _value;
        break;
        
        case 0x05: // Buffer blob
            var _bufferSize = buffer_read(_buffer, buffer_s32);
            var _bufferType = 128 - buffer_read(_buffer, buffer_u8); // 128+ is user-definable
            if (_embeddedBufferType == undefined)
            {
                _bufferType = (_bufferType >= 0 or _bufferType < 4) ? _bufferType : buffer_grow;
            }
            else
            {
                _bufferType = _embeddedBufferType;
            }
			
			// Skip if user doesn't care about the buffers
			if (_skipEmbeddedBuffers)
			{
	            buffer_seek(_buffer, buffer_seek_relative, _bufferSize);
			}
			else
			{
	            var _value = buffer_create(_bufferSize, _bufferType, 1);
	            buffer_copy(_buffer, buffer_tell(_buffer), _bufferSize, _value, 0);
	            buffer_seek(_buffer, buffer_seek_relative, _bufferSize);
            
				__SnapBufferReadBSONAddToContainer(_container, _name, _value);
			}
            
            return _value;
        
        case 0x06: // undefined
            __SnapBufferReadBSONAddToContainer(_container, _name, undefined);
		    show_debug_message("SnapBSON: Undefined is a deprecated type, please avoid use");
            return undefined;
        break;
        
        case 0x07: // objectID
            _value = new SnapBSONObjectID(undefined);
            _value.FromBuffer(_buffer);
            __SnapBufferReadBSONAddToContainer(_container, _name, _value);
            return _value;
        
        case 0x08: // boolean
            var _value = bool(buffer_read(_buffer, buffer_u8));
            __SnapBufferReadBSONAddToContainer(_container, _name, _value);
            return _value;
        break;
        
        case 0x09: // UTC datetime
            _value = new SnapBSONUTCDateTime(undefined);
            _value.FromBuffer(_buffer);
            __SnapBufferReadBSONAddToContainer(_container, _name, _value);
            return _value;
        break;
        
        case 0x0A: // <null>
            __SnapBufferReadBSONAddToContainer(_container, _name, pointer_null);
            return pointer_null;
        break;
        
        case 0x0B: // <regex>
            var _value = new SnapBSONRegex();
            _value.FromBuffer(_buffer);
            __SnapBufferReadBSONAddToContainer(_container, _name, _value);
            return _value;
        break;
        
        case 0x0C: // DB pointer
            // Deprecated so we skip past it
            buffer_read(_buffer, buffer_s32); // Skip past string size
            buffer_read(_buffer, buffer_string);
            
            repeat(4)
            {
                buffer_read(_buffer, buffer_u32);
            }
            
            show_debug_message("SNAP Warning: Deprecated BSON type detected \"db pointer\" for \"" + _name + "\". Skipping past.");
            
            return undefined;
        break;
            
        case 0x0D: // JS Code
            // Skipping past because unsupported
            var _value = new SnapBSONJSCode();
            _value.FromBuffer(_buffer);
            __SnapBufferReadBSONAddToContainer(_container, _name, _value);
            return _value;
        break;
        
        case 0x0E: // symbol
            // Deprecated so we skip past
            buffer_read(_buffer, buffer_s32); // Skip past string size
            buffer_read(_buffer, buffer_string);
            
            show_debug_message("SNAP Warning: Deprecated BSON type detected \"symbol\" for \"" + _name + "\". Skipping past.");
            return _value;
        break;
            
        case 0x0F: // JS Code with scope
            // Skipping past because unsupported
            buffer_read(_buffer, buffer_s32); // Skip past string size
            buffer_read(_buffer, buffer_string);
            
            var _size = buffer_read(_buffer, buffer_s32);
            buffer_seek(_buffer, buffer_seek_relative, _size - 4);
            
            show_debug_message("SNAP Warning: Deprecated BSON type detected \"js code with scope\" for \"" + _name + "\". Skipping past.");
            
            return undefined;
        break;
        
        case 0x10: // s32
            var _value = buffer_read(_buffer, buffer_s32);
            __SnapBufferReadBSONAddToContainer(_container, _name, _value);
            return buffer_read(_buffer, _value);
        break;
        
        case 0x11: // u64
            int64(buffer_read(_buffer, buffer_u64));
            
            show_debug_message("SNAP Warning: Unsupported BSON type detected \"uint64\" for \"" + _name + "\". Skipping past.");
            return undefined;
        break;
        
        case 0x12: // s64
            var _value = int64(buffer_read(_buffer, buffer_u64));
            __SnapBufferReadBSONAddToContainer(_container, _name, _value);
            return _value;
        break;
        
        case 0x13: // decimal128
            int64(buffer_read(_buffer, buffer_u64));
            int64(buffer_read(_buffer, buffer_u64));
            
            show_debug_message("SNAP Warning: Unsupported BSON type detected \"decimal128\" for \"" + _name + "\". Skipping past.");
            return undefined;
        break;
        
        case 0xFF: // minkey
            return undefined;
        break;
        
        case 0x7F: // maxkey
            return undefined;
        break;
        
        default:
            show_error("SNAP:\nUnsupported datatype " + string(buffer_peek(_buffer, buffer_u8, buffer_tell(_buffer)-1)) + " (position = " + string(buffer_tell(_buffer) - 1) + ")\n of name " + _name + "\n", false);
        break;
    }
}

function __SnapBufferReadBSONAddToContainer(_container, _name, _value)
{
    if (is_undefined(_container))
    {
        return;
    }
    else if (is_struct(_container))
    {
        _container[$ _name] = _value;
    }
    else if (is_array(_container))
    {
        array_push(_container, _value);
    }
    else
    {
        show_error("SNAP:\nBSON Read add to container failed. \n", true);
    }
}