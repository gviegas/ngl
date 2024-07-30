# ngl

[ngl](ngl) contains the graphics API wrapper.

[sample](sample) contains sample programs.


## ADS Sample
[sample/src/ads](sample/src/ads)
```sh
cd sample && zig build ads
```
![ADS sample](sample/capture/ads.png)


## PBR Sample
[sample/src/pbr](sample/src/pbr)
```sh
cd sample && zig build pbr
```
![PBR sample](sample/capture/pbr.png)


## PCF Sample
[sample/src/pcf](sample/src/pcf)
```sh
cd sample && zig build pcf
```
![PCF sample](sample/capture/pcf.png)


## VSM Sample
[sample/src/vsm](sample/src/vsm)
```sh
cd sample && zig build vsm
```
![VSM sample](sample/capture/vsm.png)


## SSAO Sample
[sample/src/ssao](sample/src/ssao)
```sh
cd sample && zig build ssao
```
![SSAO sample - direct lighting only](sample/capture/ssao_color.png)
![SSAO sample - ambient occlusion computation](sample/capture/ssao_ao.png)
![SSAO sample - final](sample/capture/ssao_final.png)


## IBL Sample
[sample/src/ibl](sample/src/ibl)
```sh
cd sample && zig build ibl
```
![IBL sample - black (dielectric) and nickel (conductor)](sample/capture/ibl_black_and_nickel.png)
![IBL sample - magenta (dielectric) and silver (conductor)](sample/capture/ibl_magenta_and_silver.png)
![IBL sample - white (dielectric) and gold (conductor)](sample/capture/ibl_white_and_gold.png)
