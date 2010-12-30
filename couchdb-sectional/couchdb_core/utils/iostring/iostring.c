#include "ruby.h"
#include "ruby/io.h"

VALUE TiedWriter = Qnil;

extern VALUE rb_io_get_write_io(VALUE io);
extern void rb_io_check_initialized(rb_io_t *fptr);

// duplicated from io.c
#define GetWriteIO(io) rb_io_get_write_io(io)


// shamelessly copied from HEAD.

VALUE
rb_io_set_write_io(VALUE io, VALUE w)
{
    VALUE write_io;
    rb_io_check_initialized(RFILE(io)->fptr);
    if (!RTEST(w)) {
      w = 0;
    }
    else {
      GetWriteIO(w);
    }
    write_io = RFILE(io)->fptr->tied_io_for_writing;
    RFILE(io)->fptr->tied_io_for_writing = w;
    return write_io ? write_io : Qnil;
}

void Init_iostring() {
  TiedWriter = rb_define_module("TiedWriter");
  rb_define_method(TiedWriter,"write_io=",rb_io_set_write_io,1);
  rb_define_method(TiedWriter,"write_io",rb_io_get_write_io,0);
}
