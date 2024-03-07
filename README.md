# ngl

[ngl/ngl](ngl) contains the graphics API wrapper.

[ngl/sample](sample) contains sample programs.


## ADS Sample
```sh
cd sample && zig build ads
```
![ADS sample](sample/capture/ads.png)


## PBR Sample
```sh
cd sample && zig build pbr
```
![PBR sample](sample/capture/pbr.png)


## PCF Sample
```sh
cd sample && zig build pcf
```
![PCF sample](sample/capture/pcf.png)


## VSM Sample
```sh
cd sample && zig build vsm
```
![VSM sample](sample/capture/vsm.png)


## sRGB Sample
```sh
cd sample && zig build srgb
```
![sRGB sample (EOTF)](sample/capture/srgb_eotf.png)
![sRGB sample (gamma 2.2](sample/capture/srgb_gamma_2_2.png)


## Alpha Test Sample
```sh
cd sample && zig build mag
```
![Alpha test sample (min)](sample/capture/alpha_test_min.png)
![Alpha test sample (wiggles)](sample/capture/alpha_test_wiggles.png)


## Cube Map Sample
```sh
cd sample && zig build cube
```
![Cube map sample](sample/capture/cube_map.png)


## SSAO Sample
```sh
cd sample && zig build ssao
```
![SSAO sample](sample/capture/ssao.png)


## HDR Sample
```sh
cd sample && zig build hdr
```
![HDR sample (clamp LDR)](sample/capture/hdr_clamp.png)
![HDR sample (bloom extraction)](sample/capture/hdr_bloom.png)
![HDR sample (luminance downsample)](sample/capture/hdr_luminance.png)
![HDR sample (tone map)](sample/capture/hdr_tone_map.png)
![HDR sample (final)](sample/capture/hdr_final.png)
