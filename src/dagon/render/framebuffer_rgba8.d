/*
Copyright (c) 2019 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.render.framebuffer_rgba8;

import std.stdio;

import dlib.core.memory;
import dlib.core.ownership;
import dlib.image.color;

import dagon.core.bindings;
import dagon.render.framebuffer;

class FramebufferRGBA8: Framebuffer
{    
    GLuint framebuffer;
    GLuint _colorTexture = 0;
    GLuint _depthTexture = 0;
    
    this(uint w, uint h, Owner owner)
    {
        super(w, h, owner);
    }
    
    void createFramebuffer()
    {
        releaseFramebuffer();
        
        glActiveTexture(GL_TEXTURE0);
        
        glGenTextures(1, &_colorTexture);
        glBindTexture(GL_TEXTURE_2D, _colorTexture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        glGenTextures(1, &_depthTexture);
        glBindTexture(GL_TEXTURE_2D, _depthTexture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH24_STENCIL8, width, height, 0, GL_DEPTH_STENCIL, GL_UNSIGNED_INT_24_8, null);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        glGenFramebuffers(1, &framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _colorTexture, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, _depthTexture, 0);
        
        GLenum[1] drawBuffers = [GL_COLOR_ATTACHMENT0];
        glDrawBuffers(drawBuffers.length, drawBuffers.ptr);
        
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if (status != GL_FRAMEBUFFER_COMPLETE)
            writeln(status);

        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
    
    void releaseFramebuffer()
    {
        if (glIsFramebuffer(framebuffer))
            glDeleteFramebuffers(1, &framebuffer);
        
        if (glIsTexture(_colorTexture))
            glDeleteTextures(1, &_colorTexture);
        
        if (glIsTexture(_depthTexture))
            glDeleteTextures(1, &_depthTexture);
    }
    
    ~this()
    {
        releaseFramebuffer();
    }
    
    override GLuint colorTexture()
    {
        return _colorTexture;
    }
    
    override GLuint depthTexture()
    {
        return _depthTexture;
    }
    
    override void clearColor(Color4f color)
    {
        // TODO
    }
    
    override void clearDepth(float value)
    {
        // TODO
    }
    
    override void bind()
    {
        // TODO
    }
    
    override void unbind()
    {
        // TODO
    }
    
    override void resize(uint width, uint height)
    {
        // TODO
    }
    
    override void blitColor(Framebuffer target)
    {
        // TODO
    }
    
    override void blitDepth(Framebuffer target)
    {
        // TODO
    }
}