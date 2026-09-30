using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Shapes;

namespace WdcShell
{
    /// <summary>
    /// 界面控件的引用与会话状态。
    /// 由 MainWindow.Bind() 在窗口加载后填充，其余模块只读使用。
    /// </summary>
    public static class AppState
    {
        // 窗口与控件
        public static Window Window;

        public static StackPanel DeviceListPanel;
        public static ScrollViewer EmptyState;
        public static ScrollViewer DeviceScroller;
        public static ScrollViewer LogScroller;

        public static TextBlock LogOutput;
        public static TextBlock StatusLabel;
        public static TextBlock PageTitle;
        public static TextBlock PageSubtitle;
        public static TextBlock GhostCount;
        public static TextBlock ProtectedCount;
        public static TextBlock RemovedCount;
        public static TextBlock StatusBarMain;
        public static TextBlock StatusBarCount;

        public static Ellipse StatusDot;
        public static Border ProgressFill;

        public static Button BtnScan;
        public static Button BtnRemove;
        public static Button BtnClear;

        // 会话状态
        /// <summary>本次扫描得到的设备</summary>
        public static readonly List<DeviceItem> Devices = new List<DeviceItem>();

        /// <summary>设备列表里每一行的勾选框，顺序与渲染顺序一致</summary>
        public static readonly List<CheckBox> CheckBoxes = new List<CheckBox>();

        /// <summary>本次会话累计移除数量</summary>
        public static int RemovedTotal;

        /// <summary>是否正在执行耗时操作（扫描 / 移除）</summary>
        public static bool Busy;
    }
}