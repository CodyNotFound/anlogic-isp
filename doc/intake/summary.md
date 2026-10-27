# colorshading 片上颜色校正集成需求梳理

## Task Summary
将已验证BGGR白场空间校正、逐帧AWB、颜色增强和显示映射接入colorshading项目。保留现有MIPI/DDR/HDMI平台与外部端口，不烧录。
## Confirmed Facts
目标PH1P35MDG324，1280x720，RAW10四像素/拍，RGB888四像素/拍；入口td_project/camera_to_dsi_display.al，顶层design_top_wrapper。当前BLC旁路、ISP扫描AWB、显示AWB并存。
## Hardware Dependency
hw_dependency: partial。复用既有引脚/时钟，新增模块在ISP像素时钟域；不新增CDC或物理约束。
## Assumptions and Defaults
BGGR基于当前实物确认；RAW低10位为当前beat第0像素。黑电平暂定67，可参数旁路。以两种白场空间表的几何均值为固定基表，初始全局AWB采用室内白点R=522/256,B=421/256；AWB逐帧自适应。空间表不按场景重学。
## Missing Information
无阻塞的接口信息缺失。实烧bit与当前源码对应、镜头/光源绝对色彩、最终资源时序需后续验证。
## Evidence Needed
原始数据/标定哈希、源集登记、模块数值仿真或可运行验证脚本、集成说明。保持代码验证与板上画质分离。
## Acceptance Criteria
新文件进入.al；BLC/LSC只做一次，主AWB只保留一个；sidebands随流水线对齐；支持参数旁路；输入输出吞吐不降低；ROM可复现生成；不含逐图拟合；保留回退说明。
## Handoff and Next Step
先fpga-architecture冻结三个模块与isp_top集成契约，然后逐模块fpga-rtl-build。必要编译/仿真属于验证阶段，不声称完成上板。

## 2026-10-14 Board Debug Update
用户反馈闪动、蓝色区域间歇变黄、右侧出现左侧重复。v7 STA已复核：SWNS +0.125ns、STNS 0、HWNS +0.020ns、HTNS 0；静态时序通过不等于功能/CDC通过。
源代码确认外部ISP SOF与首个128bit字同拍，而legacy video_in用SOF展宽并跨DDR域复位写FIFO，导致帧首写入数据被清除。排查和最小修复范围是isp_top的native帧开始契约；不调整颜色算法、Bayer或标定表。
验收：真实video_in和真实生成FIFO的仿真复现同拍SOF丢字，提前SOF无丢字；实际ISP到首有效字的提前余量足够FIFO复位；输出每行240个128bit字；新源重新TD Check/Synthesis/PHY；实物画质需新bit上板后复验。待确认用户烧录的准确bit版本，不阻塞源码诊断。

v9任务边界：修复AWB/HE/AB开关硬绑关闭及Bayer首行/左边界相位补齐；保持外部提前SOF、全视场及现有空间标定。综合和PHY沿用用户授权；不烧录。偏黄为待测问题，恢复AWB控制用于对照。通知缺陷：旧Wait-Process仅写报告，未创建聊天唤醒；新任务必须显式配置聊天跟进并说明其时效边界。
