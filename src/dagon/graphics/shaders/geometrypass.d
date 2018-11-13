/*
Copyright (c) 2017-2018 Timur Gafarov

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

module dagon.graphics.shaders.geometrypass;

import std.stdio;
import std.math;

import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.math.interpolation;
import dlib.image.color;

import dagon.core.libs;
import dagon.core.ownership;
import dagon.graphics.rc;
import dagon.graphics.shadow;
import dagon.graphics.texture;
import dagon.graphics.material;
import dagon.graphics.shader;

class GeometryPassShader: Shader
{
    string vs = import("GeometryPass.vs");
    string fs = import("GeometryPass.fs");

    this(Owner o)
    {
        auto myProgram = New!ShaderProgram(vs, fs, this);
        super(myProgram, o);
    }

    override void bind(RenderingContext* rc)
    {
        auto idiffuse = "diffuse" in rc.material.inputs;
        auto inormal = "normal" in rc.material.inputs;
        auto iheight = "height" in rc.material.inputs;
        auto ipbr = "pbr" in rc.material.inputs;
        auto iroughness = "roughness" in rc.material.inputs;
        auto imetallic = "metallic" in rc.material.inputs;
        auto iemission = "emission" in rc.material.inputs;
        auto ienergy = "energy" in rc.material.inputs;
        auto iparallax = "parallax" in rc.material.inputs;

        int parallaxMethod = iparallax.asInteger;
        if (parallaxMethod > ParallaxOcclusionMapping)
            parallaxMethod = ParallaxOcclusionMapping;
        if (parallaxMethod < 0)
            parallaxMethod = 0;

        setParameter("layer", rc.layer);
        setParameter("blurMask", rc.blurMask);

        setParameter("modelViewMatrix", rc.modelViewMatrix);
        setParameter("projectionMatrix", rc.projectionMatrix);
        setParameter("normalMatrix", rc.normalMatrix);

        setParameter("prevModelViewProjMatrix", rc.prevModelViewProjMatrix);
        setParameter("blurModelViewProjMatrix", rc.blurModelViewProjMatrix);

        // Diffuse
        if (idiffuse.texture)
        {
            glActiveTexture(GL_TEXTURE0);
            idiffuse.texture.bind();
            setParameter("diffuseTexture", cast(int)0);
            setParameterSubroutine("diffuse", ShaderType.Fragment, "diffuseColorTexture");
        }
        else
        {
            setParameter("diffuseVector", rc.material.diffuse.asVector4f);
            setParameterSubroutine("diffuse", ShaderType.Fragment, "diffuseColorValue");
        }

        // Normal/height
        bool haveHeightMap = inormal.texture !is null;
        if (haveHeightMap)
            haveHeightMap = inormal.texture.image.channels == 4;

        if (!haveHeightMap)
        {
            if (inormal.texture is null)
            {
                if (iheight.texture !is null) // we have height map, but no normal map
                {
                    Color4f color = Color4f(0.5f, 0.5f, 1.0f, 0.0f); // default normal pointing upwards
                    inormal.texture = rc.material.makeTexture(color, iheight.texture);
                    haveHeightMap = true;
                }
            }
            else
            {
                if (iheight.texture !is null) // we have both normal and height maps
                {
                    inormal.texture = rc.material.makeTexture(inormal.texture, iheight.texture);
                    haveHeightMap = true;
                }
            }
        }

        if (inormal.texture)
        {
            setParameter("normalTexture", 1);
            setParameterSubroutine("normal", ShaderType.Fragment, "normalMap");

            glActiveTexture(GL_TEXTURE1);
            inormal.texture.bind();
        }
        else
        {
            setParameter("normalVector", rc.material.normal.asVector3f);
            setParameterSubroutine("normal", ShaderType.Fragment, "normalValue");
        }

        // Height and parallax

        // TODO: make these material properties
        float parallaxScale = 0.03f;
        float parallaxBias = -0.01f;
        setParameter("parallaxScale", parallaxScale);
        setParameter("parallaxBias", parallaxBias);

        if (haveHeightMap)
        {
            setParameterSubroutine("height", ShaderType.Fragment, "heightMap");
        }
        else
        {
            float h = 0.0f; //-parallaxBias / parallaxScale;
            setParameter("heightScalar", h);
            setParameterSubroutine("height", ShaderType.Fragment, "heightValue");
            parallaxMethod = ParallaxNone;
        }

        if (parallaxMethod == ParallaxSimple)
            setParameterSubroutine("parallax", ShaderType.Fragment, "parallaxSimple");
        else if (parallaxMethod == ParallaxOcclusionMapping)
            setParameterSubroutine("parallax", ShaderType.Fragment, "parallaxOcclusionMapping");
        else
            setParameterSubroutine("parallax", ShaderType.Fragment, "parallaxNone");

        // PBR
        // TODO: pass solid values as uniforms, make subroutine for each mode
        if (ipbr is null)
        {
            rc.material.setInput("pbr", 0.0f);
            ipbr = "pbr" in rc.material.inputs;
        }

        if (ipbr.texture is null)
            ipbr.texture = rc.material.makeTexture(*iroughness, *imetallic, materialInput(0.0f), materialInput(0.0f));
        glActiveTexture(GL_TEXTURE2);
        ipbr.texture.bind();
        setParameter("pbrTexture", 2);

        // Emission
        if (iemission.texture)
        {
            glActiveTexture(GL_TEXTURE3);
            iemission.texture.bind();

            setParameter("emissionTexture", 3);
            setParameterSubroutine("emission", ShaderType.Fragment, "emissionMap");
        }
        else
        {
            setParameter("emissionVector", rc.material.emission.asVector4f);
            setParameterSubroutine("emission", ShaderType.Fragment, "emissionValue");
        }

        setParameter("emissionEnergy", ienergy.asFloat);

        glActiveTexture(GL_TEXTURE0);

        super.bind(rc);
    }

    override void unbind(RenderingContext* rc)
    {
        super.unbind(rc);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, 0);

        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, 0);

        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, 0);

        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, 0);

        glActiveTexture(GL_TEXTURE4);
        glBindTexture(GL_TEXTURE_2D, 0);

        glActiveTexture(GL_TEXTURE5);
        glBindTexture(GL_TEXTURE_2D_ARRAY, 0);

        glActiveTexture(GL_TEXTURE6);
        glBindTexture(GL_TEXTURE_2D, 0);

        glActiveTexture(GL_TEXTURE7);
        glBindTexture(GL_TEXTURE_2D, 0);

        glActiveTexture(GL_TEXTURE8);
        glBindTexture(GL_TEXTURE_2D, 0);

        glActiveTexture(GL_TEXTURE0);
    }
}
