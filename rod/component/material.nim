import nimx.image
import nimx.resource
import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.system_logger
import nimx.matrixes

import rod.node
import rod.component.mesh_component
import rod.component.material_shaders
import rod.component.light
import rod.quaternion
import rod.vertex_data_info

when not defined(ios) and not defined(android) and not defined(js):
    import opengl

type Attrib = enum
    aPosition
    aTexCoord
    aNormal
    aBinormal
    aTangent

type ShaderMacro = enum
    WITH_V_POSITION
    WITH_V_TEXCOORD
    WITH_V_NORMAL
    WITH_V_BINORMAL
    WITH_V_TANGENT
    WITH_AMBIENT_SAMPLER
    WITH_GLOSS_SAMPLER
    WITH_SPECULAR_SAMPLER
    WITH_NORMAL_SAMPLER
    WITH_BUMP_SAMPLER
    WITH_MATERIAL_AMBIENT
    WITH_MATERIAL_DIFFUSE
    WITH_MATERIAL_SPECULAR
    WITH_MATERIAL_SHININESS
    WITH_LIGHT_POSITION
    WITH_LIGHT_AMBIENT
    WITH_LIGHT_DIFFUSE
    WITH_LIGHT_SPECULAR
    WITH_LIGHT_DYNAMIC_ATTENUATION
    WITH_LIGHT_PRECOMPUTED_ATTENUATION
    WITH_TBN_FROM_NORMALS

type MaterialColor* = ref object of RootObj
    ambient: Vector4
    diffuse: Vector4 
    specular: Vector4 
    shininess: float32
    
    ambientInited: bool
    diffuseInited: bool
    specularInited: bool
    shininessInited: bool

proc newMaterialWithDefaultColor*(): MaterialColor = 
    result.new()
    result.ambient = newVector4(0.0, 0.0, 0.0, 1.0)
    result.diffuse = newVector4(0.3, 0.3, 0.3, 1.0)
    result.specular = newVector4(0.8, 0.8, 0.8, 1.0)
    result.shininess = 10.0
    
    result.ambientInited = true
    result.diffuseInited = true
    result.specularInited = true
    result.shininessInited = true

type TransformInfo* = ref object of RootObj
    modelMatrix*: Matrix4
    normalMatrix*: Matrix3
    scale: Vector3
    rotation: Quaternion
    translation: Vector3

proc newTransformInfoWithIdentity*(): TransformInfo = 
    result.new()
    result.scale = newVector3(1.0, 1.0, 1.0)
    result.rotation = newQuaternion()
    result.translation = newVector3(0.0, 0.0, 0.0)
    result.modelMatrix.loadIdentity()
    result.normalMatrix.loadIdentity()

proc fromScaleRotationTranslation(t: TransformInfo, scale: Vector3, rotation: Quaternion, translation: Vector3) =
    var bTransl, bScale, bRot: bool
    if t.scale != scale and scale.x != 0 and scale.y != 0 and scale.z != 0:
        t.scale = scale
        bScale = true
    if t.rotation != rotation:
        t.rotation = rotation
        bRot = true
    if t.translation != translation:
        t.translation = translation
        bTransl = true
    if bScale or bRot or bTransl:
        t.modelMatrix.loadIdentity()
        t.modelMatrix.translate(t.translation)
        t.modelMatrix.multiply(t.rotation.toMatrix4(), t.modelMatrix)
        t.modelMatrix.scale(t.scale)
        # toInversedMatrix3 proc asserts with zero matrix( and on scale == 0)
        t.modelMatrix.toInversedMatrix3(t.normalMatrix)
        t.normalMatrix.transpose()

type Material* = ref object of RootObj
    albedoTexture*: Image
    glossTexture*: Image
    specularTexture*: Image
    normalTexture*: Image
    bumpTexture*: Image

    color: MaterialColor
    transform: TransformInfo
    light*: LightSource

    # TODO
    # useNormals: bool
    # useNormalMap: bool
    # useLight: bool
    # TODO

    blendEnable*: bool
    depthEnable*: bool
    isWireframe*: bool
    
    vertexShader*: string
    fragmentShader*: string
    shader*: GLuint
    bShaderNeedUpdate: bool
    shaderMacroFlags: set[ShaderMacro]

proc shaderNeedUpdate(m: Material) = 
    m.bShaderNeedUpdate = true

proc setAmbientColor*(m: Material, x, y, z: Coord) = 
    m.color.ambient = newVector4(x, y, z, 1.0)
    m.color.ambientInited = true
    m.shaderNeedUpdate()

proc setAmbientColor*(m: Material, x, y, z, w: Coord) = 
    m.color.ambient = newVector4(x, y, z, w)
    m.color.ambientInited = true
    m.shaderNeedUpdate()

proc removeAmbientColor*(m: Material) = 
    m.color.ambientInited = false
    m.shaderMacroFlags.excl(WITH_MATERIAL_AMBIENT)
    m.shaderNeedUpdate()

proc setDiffuseColor*(m: Material, x, y, z: Coord) = 
    m.color.diffuse = newVector4(x, y, z, 1.0)
    m.color.diffuseInited = true
    m.shaderNeedUpdate()

proc setDiffuseColor*(m: Material, x, y, z, w: Coord) = 
    m.color.diffuse = newVector4(x, y, z, w)
    m.color.diffuseInited = true
    m.shaderNeedUpdate()

proc removeDiffuseColor*(m: Material) = 
    m.color.diffuseInited = false
    m.shaderMacroFlags.excl(WITH_MATERIAL_DIFFUSE)
    m.shaderNeedUpdate()

proc setSpecularColor*(m: Material, x, y, z: Coord) = 
    m.color.specular = newVector4(x, y, z, 1.0)
    m.color.specularInited = true
    m.shaderNeedUpdate()

proc setSpecularColor*(m: Material, x, y, z, w: Coord) = 
    m.color.specular = newVector4(x, y, z, w)
    m.color.specularInited = true
    m.shaderNeedUpdate()

proc removeSpecularColor*(m: Material) = 
    m.color.specularInited = false
    m.shaderMacroFlags.excl(WITH_MATERIAL_SPECULAR)
    m.shaderNeedUpdate()

proc setShininess*(m: Material, s: Coord) = 
    m.color.shininess = s
    m.color.shininessInited = true
    m.shaderNeedUpdate()

proc removeShininess*(m: Material) = 
    m.color.shininessInited = false
    m.shaderMacroFlags.excl(WITH_MATERIAL_SHININESS)
    m.shaderNeedUpdate()

proc newDefaultMaterial*(): Material =
    result.new()
    result.blendEnable = false
    result.depthEnable = true
    result.isWireframe = false
    
    result.color = newMaterialWithDefaultColor()
    result.transform = newTransformInfoWithIdentity()

    result.shader = 0
    result.shaderNeedUpdate()

proc updateVertexAttributesSetup*(m: Material, vertInfo: VertexDataInfo) =
    let c = currentContext()
    let gl = c.gl

    var ofset: int = 0

    if vertInfo.numOfCoordPerVert != 0: 
        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, vertInfo.numOfCoordPerVert, gl.FLOAT, false, vertInfo.stride.GLsizei , ofset)
        ofset += vertInfo.numOfCoordPerVert * sizeof(GLfloat)
    if vertInfo.numOfCoordPerTexCoord != 0:
        if m.shader == 0:
            m.shaderMacroFlags.incl(WITH_V_TEXCOORD)
        gl.enableVertexAttribArray(aTexCoord.GLuint)
        gl.vertexAttribPointer(aTexCoord.GLuint, vertInfo.numOfCoordPerTexCoord, gl.FLOAT, false, vertInfo.stride.GLsizei , ofset)
        ofset += vertInfo.numOfCoordPerTexCoord * sizeof(GLfloat)
    if vertInfo.numOfCoordPerNormal != 0:
        if m.shader == 0:
            m.shaderMacroFlags.incl(WITH_V_NORMAL)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        gl.enableVertexAttribArray(aNormal.GLuint)
        gl.vertexAttribPointer(aNormal.GLuint, vertInfo.numOfCoordPerNormal, gl.FLOAT, false, vertInfo.stride.GLsizei , ofset)
        ofset += vertInfo.numOfCoordPerNormal * sizeof(GLfloat)
    if vertInfo.numOfCoordPerBinormal != 0:
        if m.shader == 0: 
            m.shaderMacroFlags.incl(WITH_V_BINORMAL)
        gl.enableVertexAttribArray(aBinormal.GLuint)
        gl.vertexAttribPointer(aBinormal.GLuint, vertInfo.numOfCoordPerBinormal, gl.FLOAT, false, vertInfo.stride.GLsizei , ofset)
        ofset += vertInfo.numOfCoordPerBinormal * sizeof(GLfloat)
    if vertInfo.numOfCoordPerTangent != 0:
        if m.shader == 0: 
            m.shaderMacroFlags.incl(WITH_V_TANGENT)
        gl.enableVertexAttribArray(aTangent.GLuint)
        gl.vertexAttribPointer(aTangent.GLuint, vertInfo.numOfCoordPerTangent, gl.FLOAT, false, vertInfo.stride.GLsizei , ofset)
        ofset += vertInfo.numOfCoordPerTangent * sizeof(GLfloat)

proc setupSamplerAttributes(m: Material) = 
    let c = currentContext()
    let gl = c.gl

    var theQuad {.noinit.}: array[4, GLfloat]
    var textureIndex : GLint = 0

    if not m.albedoTexture.isNil:
        if m.shader == 0: 
            m.shaderMacroFlags.incl(WITH_AMBIENT_SAMPLER)
        else:
            gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
            gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.albedoTexture, gl, theQuad))
            gl.uniform4fv(gl.getUniformLocation(m.shader, "uTexUnitCoords"), theQuad)
            gl.uniform1i(gl.getUniformLocation(m.shader, "texUnit"), textureIndex)
            inc textureIndex
    if not m.glossTexture.isNil:
        if m.shader == 0: 
            m.shaderMacroFlags.incl(WITH_GLOSS_SAMPLER)
        else:
            gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
            gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.glossTexture, gl, theQuad))
            gl.uniform4fv(gl.getUniformLocation(m.shader, "uGlossUnitCoords"), theQuad)
            gl.uniform1i(gl.getUniformLocation(m.shader, "glossMapUnit"), textureIndex)
            inc textureIndex
    if not m.specularTexture.isNil:
        if m.shader == 0: 
            m.shaderMacroFlags.incl(WITH_SPECULAR_SAMPLER)
        else:
            gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
            gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.specularTexture, gl, theQuad))
            gl.uniform4fv(gl.getUniformLocation(m.shader, "uSpecularUnitCoords"), theQuad)
            gl.uniform1i(gl.getUniformLocation(m.shader, "specularMapUnit"), textureIndex)
            inc textureIndex
    if not m.normalTexture.isNil:
        if m.shader == 0: 
            m.shaderMacroFlags.incl(WITH_NORMAL_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
            gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.normalTexture, gl, theQuad))
            gl.uniform4fv(gl.getUniformLocation(m.shader, "uNormalUnitCoords"), theQuad)
            gl.uniform1i(gl.getUniformLocation(m.shader, "normalMapUnit"), textureIndex)
            inc textureIndex
    if not m.bumpTexture.isNil:
        if m.shader == 0:
            m.shaderMacroFlags.incl(WITH_BUMP_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
            gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.bumpTexture, gl, theQuad))
            gl.uniform4fv(gl.getUniformLocation(m.shader, "uBumpUnitCoords"), theQuad)
            gl.uniform1i(gl.getUniformLocation(m.shader, "bumpMapUnit"), textureIndex)
            inc textureIndex

proc setupMaterialAttributes(m: Material) = 
    if not m.color.isNil:
        let c = currentContext()
        let gl = c.gl

        if m.color.ambientInited:
            if m.shader == 0: 
                m.shaderMacroFlags.incl(WITH_MATERIAL_AMBIENT)
            gl.uniform4fv(gl.getUniformLocation(m.shader, "uMaterialAmbient"), m.color.ambient)

        if m.color.diffuseInited:
            if m.shader == 0: 
                m.shaderMacroFlags.incl(WITH_MATERIAL_DIFFUSE)
            else:
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uMaterialDiffuse"), m.color.diffuse)
        if m.color.specularInited:
            if m.shader == 0: 
                m.shaderMacroFlags.incl(WITH_MATERIAL_SPECULAR)
            else:
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uMaterialSpecular"), m.color.specular)
        if m.color.shininessInited:
            if m.shader == 0: 
                m.shaderMacroFlags.incl(WITH_MATERIAL_SHININESS) 
            else:
                gl.uniform1f(gl.getUniformLocation(m.shader, "uMaterialShininess"), m.color.shininess)

proc setupLightAttributes(m: Material, l:LightSource) = 
    if not l.isNil:
        let c = currentContext()
        let gl = c.gl

        if l.lightPosInited:
            if m.shader == 0: 
                m.shaderMacroFlags.incl(WITH_LIGHT_POSITION)
            else:
                let lightPosition = l.getPosition()
                # var lightPosFromWorld = m.transform.normalMatrix * lightPosition
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uLightPosition"), lightPosition)
        if l.lightAmbientInited:
            if m.shader == 0: 
                m.shaderMacroFlags.incl(WITH_LIGHT_AMBIENT)
            else:
                gl.uniform1f(gl.getUniformLocation(m.shader, "uLightAmbient"), l.getAmbient())
        if l.lightDiffuseInited:
            if m.shader == 0: 
                m.shaderMacroFlags.incl(WITH_LIGHT_DIFFUSE)
            else:
                gl.uniform1f(gl.getUniformLocation(m.shader, "uLightDiffuse"), l.getDiffuse())
        if l.lightSpecularInited:
            if m.shader == 0: 
                m.shaderMacroFlags.incl(WITH_LIGHT_SPECULAR)
            else:
                gl.uniform1f(gl.getUniformLocation(m.shader, "uLightSpecular"), l.getSpecular())
        if l.lightAttenuationInited:
            if m.shader == 0: 
                m.shaderMacroFlags.incl(WITH_LIGHT_PRECOMPUTED_ATTENUATION)
            else:
                gl.uniform1f(gl.getUniformLocation(m.shader, "uAttenuation"), l.getAttenuation())
        elif l.lightConstantInited and l.lightLinearInited and l.lightQuadraticInited:
            if m.shader == 0:
                m.shaderMacroFlags.incl(WITH_LIGHT_DYNAMIC_ATTENUATION)
            else:
                gl.uniform1f(gl.getUniformLocation(m.shader, "uLightConstant"), l.getConstant())
                gl.uniform1f(gl.getUniformLocation(m.shader, "uLightLinear"), l.getLinear())
                gl.uniform1f(gl.getUniformLocation(m.shader, "uLightQuadratic"), l.getQuadratic())

proc setupNormalMappingTechniqueWithoutPrecomputedTangents*(m: Material) = 
    if m.shader == 0: 
        m.shaderMacroFlags.incl(WITH_TBN_FROM_NORMALS)

proc updateTransformSetup*(m: Material, translation: Vector3, rotation: Quaternion, scale: Vector3) =
    m.transform.fromScaleRotationTranslation(scale, rotation, translation)

proc createShader(m: Material) = 
    let c = currentContext()
    let gl = c.gl

    #TODO delete shader prog from gl if exist 
    m.shader = 0

    var commonShaderDefines = ""
    for macros in m.shaderMacroFlags:
        commonShaderDefines &= """#define """ & $macros & "\n"

    if m.vertexShader.len == 0:
        m.vertexShader = ""
        m.vertexShader &= commonShaderDefines & materialVertexShaderDefault

    if m.fragmentShader.len == 0:
        m.fragmentShader = ""
        m.fragmentShader &= commonShaderDefines & materialFragmentShaderDefault

    m.shader = gl.newShaderProgram(m.vertexShader, m.fragmentShader, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord), 
                                    (aNormal.GLuint, $aNormal), (aTangent.GLuint, $aTangent), (aBinormal.GLuint, $aBinormal)])
    m.bShaderNeedUpdate = false

proc assignShaders*(m: Material, vertexShader: string = "", fragmentShader: string = "") =
    m.vertexShader = vertexShader
    m.fragmentShader = fragmentShader
    m.shaderNeedUpdate()

# proc assignShadersWithResource*(m: Material, vertexShader: string = "", fragmentShader: string = "") =
#     if vertexShader != "": 
#         loadResourceAsync vertexShader, proc(s: Stream) =
#             m.vertexShader = s.readAll()
#             s.close()
#     else: 
#         m.vertexShader = vertexShaderDefault

#     if fragmentShader != "": 
#         loadResourceAsync fragmentShader, proc(s: Stream) =
#             m.fragmentShader = s.readAll()
#             s.close()
#     else: 
#         m.fragmentShader = fragmentShaderDefault

method initSetup*(m: Material) = discard

method updateSetup*(m: Material) = 
    let c = currentContext()
    let gl = c.gl

    if m.shader == 0 or m.bShaderNeedUpdate:
        m.setupSamplerAttributes()
        m.setupMaterialAttributes()
        m.setupLightAttributes(m.light)
        #TODO use techniques
        m.setupNormalMappingTechniqueWithoutPrecomputedTangents()
        m.createShader()
 
    gl.useProgram(m.shader)

    m.setupSamplerAttributes()
    m.setupMaterialAttributes()
    m.setupLightAttributes(m.light)   
    
    c.setTransformUniform(m.shader)
    
    if not m.transform.isNil:
        gl.uniformMatrix4fv(gl.getUniformLocation(m.shader, "modelMatrix"), false, m.transform.modelMatrix)
        gl.uniformMatrix3fv(gl.getUniformLocation(m.shader, "normalMatrix"), false, m.transform.normalMatrix)

    if m.blendEnable:
        gl.enable(gl.BLEND)
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    else:
        gl.disable(gl.BLEND)

    if m.depthEnable:
        gl.enable(gl.DEPTH_TEST)

    when not defined(ios) and not defined(android) and not defined(js):
        glPolygonMode(GL_FRONT_AND_BACK, if m.isWireframe: GL_LINE else: GL_FILL)
