//
//  GLVideoWriter.m
//  Created by Lukasz Karluk on 28/9/17.
//  Copyright © 2017 Lukasz Karluk. All rights reserved.
//

#include "GLVideoWriter.h"
#include "ofxiOSVideoPlayer.h"
#include "ofxiOSSoundPlayer.h"
#include "ofxiOSEAGLView.h"
#import "AVFoundationVideoPlayer.h"

//-------------------------------------------------------------------------
#define STRINGIFY(x) #x

static string swizzleVertexShader = STRINGIFY(
    
    uniform mat4 modelViewProjectionMatrix;
                                              
    attribute vec4 position;
    attribute vec2 texcoord;
                                 
    varying vec2 texCoordVarying;
                                              
    void main()
    {
        texCoordVarying = texcoord;
        gl_Position = modelViewProjectionMatrix * position;
    }
);

static string swizzleFragmentShader = STRINGIFY(
                                                
    precision highp float;
                                                
    uniform sampler2D tex0;
    varying vec2 texCoordVarying;

    void main() {
        gl_FragColor = texture2D(tex0, texCoordVarying).bgra;
    }
);

//-------------------------------------------------------------------------
GLVideoWriter::GLVideoWriter() {
    videoWriter = nil;
    
    startTime = 0;
    recordFrameNum = 0;
    recordFPS = 0;
    bLockToFPS = false;
    bUseTextureCache = false;
}

GLVideoWriter::~GLVideoWriter() {
    if((videoWriter != nil)) {
        [videoWriter release];
        videoWriter = nil;
    }
}

//------------------------------------------------------------------------- setup.
void GLVideoWriter::setup(int videoWidth, int videoHeight) {
    NSString * docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString * docVideoPath = [docPath stringByAppendingPathComponent:@"/video.mov"];

    setup(videoWidth, videoHeight, [docVideoPath UTF8String]);
}

void GLVideoWriter::setup(int videoWidth, int videoHeight, string filePath) {
    if((videoWriter != nil)) {
        return;
    }
    
    CGSize videoSize = CGSizeMake(videoWidth, videoHeight);
    videoWriter = [[VideoWriter alloc] initWithPath:[NSString stringWithUTF8String:filePath.c_str()] andVideoSize:videoSize];
    videoWriter.context = [ofxiOSEAGLView getInstance].context; // TODO - this should probably be passed in with init.
    videoWriter.enableTextureCache = YES; // TODO - this should be turned on by default when it is working.
    
    shaderBGRA.setupShaderFromSource(GL_VERTEX_SHADER, swizzleVertexShader);
    shaderBGRA.setupShaderFromSource(GL_FRAGMENT_SHADER, swizzleFragmentShader);
    shaderBGRA.bindDefaults();
    shaderBGRA.linkProgram();
    
    fbo.allocate(videoWidth, videoHeight, GL_RGBA, 0);
    fboBGRA.allocate(videoWidth, videoHeight, GL_RGBA, 0);
}

void GLVideoWriter::setFPS(float fps) {
    recordFPS = fps;
    bLockToFPS = true;
}

float GLVideoWriter::getFPS() {
    return recordFPS;
}

//------------------------------------------------------------------------- update.
void GLVideoWriter::update() {
    //
}

//------------------------------------------------------------------------- draw.
void GLVideoWriter::draw(ofRectangle & rect) {
    draw(rect.x, rect.y, rect.width, rect.height);
}

void GLVideoWriter::draw(float x, float y) {
    draw(x, y, fbo.getWidth(), fbo.getHeight());
}

void GLVideoWriter::draw(float x, float y, float width, float height) {
    fbo.draw(x, y, width, height);
}

//------------------------------------------------------------------------- record api.
void GLVideoWriter::startRecording() {
    if((videoWriter == nil) ||
       [videoWriter isWriting] == YES) {
        return;
    }
    
    startTime = ofGetElapsedTimef();
    recordFrameNum = 0;

    BOOL bRealTime = (bLockToFPS == false);
    bRealTime = YES; // for some reason, if bRealTime is false, it screws things up.
    [videoWriter setExpectsMediaDataInRealTime:bRealTime];
    [videoWriter startRecording];

    if([videoWriter isTextureCached] == YES) {
        initTextureCache();
    }
}

void GLVideoWriter::cancelRecording() {
    if((videoWriter == nil) ||
       [videoWriter isWriting] == NO) {
        return;
    }
    
    [videoWriter cancelRecording];
    
    killTextureCache();
}

void GLVideoWriter::finishRecording() {
    if((videoWriter == nil) ||
       [videoWriter isWriting] == NO) {
        return;
    }
    
    [videoWriter finishRecording];

    killTextureCache();
}

bool GLVideoWriter::isRecording() {
    if((videoWriter != nil) &&
       [videoWriter isWriting] == YES) {
        return YES;
    }
    return NO;
}

int GLVideoWriter::getRecordFrameNum() {
    return recordFrameNum;
}

//------------------------------------------------------------------------- texture cache
void GLVideoWriter::initTextureCache() {
    if(bUseTextureCache == true) {
        return;
    }
    bUseTextureCache = true;
    
    unsigned int textureCacheID = [videoWriter textureCacheID];
    int textureCacheTarget = [videoWriter textureCacheTarget];
    
    int textureW = fbo.getWidth();
    int textureH = fbo.getHeight();
    
    ofTexture texture;
    texture.allocate(textureW, textureH, GL_RGBA);
    
    ofTextureData & texData = texture.getTextureData();
    texData.textureTarget = textureCacheTarget;
    texData.tex_t = 1.0f; // these values need to be reset to 1.0 to work properly.
    texData.tex_u = 1.0f; // assuming this is something to do with the way ios creates the texture cache.
    
    texture.setUseExternalTextureID(textureCacheID);
    texture.setTextureMinMagFilter(GL_LINEAR, GL_LINEAR);
    texture.setTextureWrap(GL_CLAMP_TO_EDGE, GL_CLAMP_TO_EDGE);
    if(!ofIsGLProgrammableRenderer()) {
        texture.bind();
        glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
        texture.unbind();
    }
    
    fbo.bind();
    fbo.attachTexture(texture, GL_RGBA, 0);
    fbo.unbind();
}

void GLVideoWriter::killTextureCache() {
    if(bUseTextureCache == false) {
        return;
    }
    bUseTextureCache = false;
    
    int textureW = fbo.getWidth();
    int textureH = fbo.getHeight();
    
    ofTexture texture;
    texture.allocate(textureW, textureH, GL_RGBA);
    
    fbo.bind();
    fbo.attachTexture(texture, GL_RGBA, 0);
    fbo.unbind();
}

//------------------------------------------------------------------------- begin / end.
void GLVideoWriter::begin() {
    fbo.begin();

    ofClear(0, 255);
}

void GLVideoWriter::end() {
    fbo.end();

    //----------------------------------------------
    if((videoWriter == nil) ||
       [videoWriter isWriting] == NO) {
        return;
    }
    
    //----------------------------------------------
    bool bSwizzle = (bUseTextureCache == false);
    /*
     *  texture caching automatically converts the RGB textures to BGR.
     *  but if texture caching is not being used, we have to do this using
     *  swizzle shaders.
     */
    
    if(bSwizzle) {
        
        if(shaderBGRA.isLoaded()) {
            shaderBGRA.begin();
        }
        fboBGRA.begin();
        
        fbo.draw(0, 0);
        
        fboBGRA.end();
        if(shaderBGRA.isLoaded()) {
            shaderBGRA.end();
        }
    }
    
    //---------------------------------------------- frame time.
    CMTime frameTime = kCMTimeZero;
    
    if(bLockToFPS) {
        frameTime = CMTimeMake(recordFrameNum, (int)recordFPS);
    } else {
        float time = ofGetElapsedTimef() - startTime;
        frameTime = CMTimeMakeWithSeconds(time, NSEC_PER_SEC);
    }
    
    //---------------------------------------------- add video frame.
    if(bSwizzle) {
        fboBGRA.bind();
    }

    //ofLog() << "show do wrignit " << recordFrameNum << ", " << frameTime.value;
    BOOL bVideoFrameAdded = [videoWriter addFrameAtTime:frameTime];
    if(bVideoFrameAdded == YES) {
        recordFrameNum += 1;
    }
    
    if(bSwizzle) {
        fboBGRA.unbind();
    }
}

