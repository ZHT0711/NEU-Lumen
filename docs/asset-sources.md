# 素材来源

应用图标使用内置 imagegen 生成，设计为深蓝圆章、光束 L 字、山峰与书页水纹，导出为 1024 像素 RGB PNG。

校园建筑由 SwiftUI Shape 绘制；外观参考学校公开照片，位置为视觉编排。校徽及学院图片仅作界面展示。

首页书法校名使用 README 同一份学校原版标识，界面裁出校名部分并保留原始比例，不用系统字体仿写。来源：[学校官网标识](https://www.neu.edu.cn/images/libpic/logo.png)、[东大标识](https://www.neu.edu.cn/xygk/ddbs.htm)。

- [浑南校区图库](https://hnxqgwh.neu.edu.cn/2019/0326/c2900a88675/pagem.htm)
- [一号公共教学楼](https://jjch.neu.edu.cn/2017/0825/c2837a51631/page.htm)
- [信息科学大楼](https://jjch.neu.edu.cn/2016/0319/c2837a51627/page.htm)
- [南湖校区风景](https://www.neu.edu.cn/zjdd/xyfj.htm)
- [大学文化](https://www.neu.edu.cn/xygk/dxwh.htm) · [历史沿革](https://www.neu.edu.cn/xygk/lsyg.htm)

原生服务卡面使用 SwiftUI Shape 校园简笔画，涵盖教学馆、校门、图书馆、火箭广场、体育场、银杏、食堂面碗与书桌等主题。十二项服务分别配图，深浅色与增强对比度下调整线条颜色。

楼内导航目录与点位来自 [Pathly](https://pathly.top) 公开前端，导入快照含各源文件 SHA-256；楼层平面图从原站按需加载，路线由原站服务返回，原生界面绘制线条和起终点标记。模拟器路线截图使用本次构建生成的合成楼层图，非现场截图。

“走进东大”各处题材分别为南湖/浑南校门、南湖主楼与中心花园、浑南图书馆，不复用首页的楼群线稿。主楼参考[学校校园风景](https://www.neu.edu.cn/zjdd/xyfj.htm)，图书馆参考[浑南校区校区风采](https://hnxqgwh.neu.edu.cn/2019/0326/c2900a88675/page.htm)，均为代码绘制的简笔画，未复制原照片。

室外入口配准记录在 `data/campus-entrance-alignment.json`，包含 Pathly 楼门图 URL、SHA-256、门口像素及建筑轮廓参考；运行 `python scripts/build_campus_entrances.py` 生成内置 WGS84 坐标。建筑轮廓来自 [OpenStreetMap 贡献者](https://www.openstreetmap.org/copyright)（ODbL），材料馆参考 [Esri World Imagery](https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer)。配准坐标作为衍生数据库按 ODbL 提供，未重新发布原图；坐标不是实地测绘结果。Pathly 自动化实验室楼门图及 G01→113 路线与理学院 A 门共用位置，保留原站映射并在界面提示核对。
