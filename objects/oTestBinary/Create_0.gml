vertex_format_begin();
vertex_format_add_position();
var format = vertex_format_end();
var buff   = vertex_create_buffer();
vertex_begin(buff, format);
vertex_position(buff, 0, 0);
vertex_position(buff, 0, 1);
vertex_position(buff, 1, 1);
vertex_position(buff, 1, 0);
vertex_end(buff);



struct = {
    a : true,
    b : false,
    c : undefined,
    d : 1/9,
    e : 15/100,
    array : [
        5,
        6,
        7,
        {
            struct : "struct!",
            nested : {
                nested : "nested!",
                array : [
                    "more",
                    "MORE",
                    "M O R E"
                ]
            }
        }
    ],
    test : "text!",
    test2 : "\"Hello world!\"",
    url : "https://www.jujuadams.com/",
    func : function() {},
    pointer: ptr(id),
    instance: id,
	buffer : buff,
};

show_debug_message(is_handle(struct.buffer));

buffer = SnapBufferWriteBinary(ScratchBuffer(), struct);
buffer_save(buffer, "binary.txt");
vertex_delete_buffer(buff);
struct = SnapBufferReadBinary(buffer, 0);
show_debug_message(SnapVisualize(struct));
buff = vertex_create_buffer_from_buffer(struct.buffer, format);