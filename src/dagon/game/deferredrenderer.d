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

module dagon.game.deferredrenderer;

import dlib.core.memory;
import dlib.core.ownership;

import dagon.core.event;
import dagon.core.time;
import dagon.resource.scene;
import dagon.render.deferred;
import dagon.render.gbuffer;
import dagon.render.view;
import dagon.render.framebuffer;
import dagon.render.shadowstage;
import dagon.render.framebuffer_rgba16f;
import dagon.render.framebuffer_r8;
import dagon.postproc.filterstage;
import dagon.postproc.shaders.denoise;
import dagon.game.renderer;

class DeferredRenderer: Renderer
{
    GBuffer gbuffer;

    DenoiseShader denoiseShader;

    ShadowStage stageShadow;
    DeferredClearStage stageClear;
    DeferredBackgroundStage stageBackground;
    DeferredGeometryStage stageStaticGeometry;
    DeferredDecalStage stageDecals;
    DeferredGeometryStage stageDynamicGeometry;
    DeferredOcclusionStage stageOcclusion;
    FilterStage stageOcclusionDenoise;
    DeferredEnvironmentStage stageEnvironment;
    DeferredLightStage stageLight;
    DeferredParticlesStage stageParticles;
    DeferredForwardStage stageForward;
    DeferredDebugOutputStage stageDebug;

    RenderView occlusionView;
    FramebufferR8 occlusionNoisyBuffer;
    FramebufferR8 occlusionBuffer;

    DebugOutputMode outputMode = DebugOutputMode.Radiance;
    
    bool _ssaoEnabled = true;

    int ssaoSamples = 10;
    float ssaoRadius = 0.2f;
    float ssaoPower = 7.0f;
    float ssaoDenoise = 1.0f;

    this(EventManager eventManager, Owner owner)
    {
        super(eventManager, owner);

        occlusionView = New!RenderView(0, 0, view.width / 2, view.height / 2, this);
        occlusionNoisyBuffer = New!FramebufferR8(occlusionView.width, occlusionView.height, this);
        occlusionBuffer = New!FramebufferR8(occlusionView.width, occlusionView.height, this);

        // HDR buffer
        auto radianceBuffer = New!FramebufferRGBA16f(eventManager.windowWidth, eventManager.windowHeight, this);
        outputBuffer = radianceBuffer;

        gbuffer = New!GBuffer(view.width, view.height, radianceBuffer, this);

        stageShadow = New!ShadowStage(pipeline);
        
        stageClear = New!DeferredClearStage(pipeline, gbuffer);

        stageBackground = New!DeferredBackgroundStage(pipeline, gbuffer);
        stageBackground.view = view;

        stageStaticGeometry = New!DeferredGeometryStage(pipeline, gbuffer);
        stageStaticGeometry.view = view;
        
        stageDecals = New!DeferredDecalStage(pipeline, gbuffer);
        stageDecals.view = view;
        
        stageDynamicGeometry = New!DeferredGeometryStage(pipeline, gbuffer);
        stageDynamicGeometry.view = view;

        stageOcclusion = New!DeferredOcclusionStage(pipeline, gbuffer);
        stageOcclusion.view = occlusionView;
        stageOcclusion.outputBuffer = occlusionNoisyBuffer;

        denoiseShader = New!DenoiseShader(this);
        stageOcclusionDenoise = New!FilterStage(pipeline, denoiseShader);
        stageOcclusionDenoise.view = occlusionView;
        stageOcclusionDenoise.inputBuffer = occlusionNoisyBuffer;
        stageOcclusionDenoise.outputBuffer = occlusionBuffer;

        stageEnvironment = New!DeferredEnvironmentStage(pipeline, gbuffer);
        stageEnvironment.view = view;
        stageEnvironment.outputBuffer = radianceBuffer;
        stageEnvironment.occlusionBuffer = occlusionBuffer;

        stageLight = New!DeferredLightStage(pipeline, gbuffer);
        stageLight.view = view;
        stageLight.outputBuffer = radianceBuffer;
        stageLight.occlusionBuffer = occlusionBuffer;
        
        stageParticles = New!DeferredParticlesStage(pipeline, gbuffer);
        stageParticles.view = view;
        // TODO: velocity buffer as a second attachment
        stageParticles.outputBuffer = radianceBuffer;
        
        stageForward = New!DeferredForwardStage(pipeline);
        stageForward.view = view;
        // TODO: velocity buffer as a second attachment
        stageForward.outputBuffer = radianceBuffer;

        stageDebug = New!DeferredDebugOutputStage(pipeline, gbuffer);
        stageDebug.view = view;
        stageDebug.active = false;
        stageDebug.outputBuffer = radianceBuffer;
        stageDebug.occlusionBuffer = occlusionBuffer;
    }
    
    void ssaoEnabled(bool mode) @property
    {
        _ssaoEnabled = mode;
        stageOcclusion.active = mode;
        stageOcclusionDenoise.active = mode;
        if (_ssaoEnabled)
        {
            stageEnvironment.occlusionBuffer = occlusionBuffer;
            stageLight.occlusionBuffer = occlusionBuffer;
        }
        else
        {
            stageEnvironment.occlusionBuffer = null;
            stageLight.occlusionBuffer = null;
        }
    }
    
    bool ssaoEnabled() @property
    {
        return _ssaoEnabled;
    }

    override void scene(Scene s)
    {
        stageShadow.group = s.spatial;
        stageShadow.lightGroup = s.lights;
        stageBackground.group = s.background;
        stageStaticGeometry.group = s.spatialOpaqueStatic;
        stageDecals.group = s.decals;
        stageDynamicGeometry.group = s.spatialOpaqueDynamic;
        stageLight.groupSunLights = s.sunLights;
        stageLight.groupAreaLights = s.areaLights;
        stageParticles.group = s.spatial;
        stageForward.group = s.spatialTransparent;

        stageBackground.state.environment = s.environment;
        stageStaticGeometry.state.environment = s.environment;
        stageDecals.state.environment = s.environment;
        stageDynamicGeometry.state.environment = s.environment;
        stageEnvironment.state.environment = s.environment;
        stageLight.state.environment = s.environment;
        stageParticles.state.environment = s.environment;
        stageDebug.state.environment = s.environment;
        stageForward.state.environment = s.environment;
    }

    override void update(Time t)
    {
        stageShadow.camera = activeCamera;
        stageDebug.active = (outputMode != DebugOutputMode.Radiance);
        stageDebug.outputMode = outputMode;

        stageOcclusion.ssaoShader.samples = ssaoSamples;
        stageOcclusion.ssaoShader.radius = ssaoRadius;
        stageOcclusion.ssaoShader.power = ssaoPower;
        denoiseShader.factor = ssaoDenoise;

        super.update(t);
    }

    override void setViewport(uint x, uint y, uint w, uint h)
    {
        super.setViewport(x, y, w, h);

        outputBuffer.resize(view.width, view.height);
        gbuffer.resize(view.width, view.height);

        occlusionView.resize(view.width / 2, view.height / 2);
        occlusionNoisyBuffer.resize(occlusionView.width, occlusionView.height);
        occlusionBuffer.resize(occlusionView.width, occlusionView.height);
    }
}
