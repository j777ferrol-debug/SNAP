// Feather disable all

/// @ignore
// This is being used to track some things when building a BSON buffer because BSON is a whack format.
function __SnapBSON()
{
    static _bson = undefined;
    if (_bson != undefined) return _bson;
    
    _bson = {  };
    with (_bson)
    {
        __currentDocumentLevel = undefined;
        __documentStartOffsets = undefined;
    };
    
    return _bson;
}