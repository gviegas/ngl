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


## SSAO Sample
```sh
cd sample && zig build ssao
```
![SSAO sample - direct lighting only](sample/capture/ssao_color.png)
![SSAO sample - ambient occlusion computation](sample/capture/ssao_ao.png)
![SSAO sample - final](sample/capture/ssao_final.png)


## IBL Sample
```sh
cd sample && zig build ibl
```
![IBL sample - black (dielectric) and nickel (conductor)](sample/capture/ibl_black_and_nickel.png)
![IBL sample - magenta (dielectric) and silver (conductor)](sample/capture/ibl_magenta_and_silver.png)
![IBL sample - white (dielectric) and gold (conductor)](sample/capture/ibl_white_and_gold.png)
