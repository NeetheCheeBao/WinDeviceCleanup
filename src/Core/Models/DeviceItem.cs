namespace WdcShell
{
    /// <summary>
    /// 一个设备条目。由 PowerShell 后端的制表符分隔输出解析而来。
    /// </summary>
    public class DeviceItem
    {
        /// <summary>设备友好名称，例如 "USB-SERIAL CH340 (COM3)"</summary>
        public string Name;

        /// <summary>设备实例 ID，例如 "USB\VID_1A86&amp;PID_7523\8&amp;6C022A&amp;0&amp;9"</summary>
        public string InstanceId;

        /// <summary>是否已配置 CPU 亲和性 / IRQ 绑定（这类设备默认不勾选）</summary>
        public bool IsProtected;
    }
}