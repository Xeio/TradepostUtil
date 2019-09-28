import com.Components.RightClickItem;
import com.GameInterface.DistributedValue;
import com.GameInterface.InventoryItem;
import com.GameInterface.Tradepost;
import com.Utils.Text;
import mx.utils.Delegate;
import com.Utils.Archive;
import com.Utils.ID32;
import com.Components.InventoryItemList.MCLItemInventoryItem;
import com.GameInterface.Inventory;
import com.GameInterface.Game.Character;
import com.Utils.LDBFormat;

class TradepostUtil
{    
    private var m_swfRoot: MovieClip;
    
    static var ARCHIVE_VALUES:String = "PriceHistoryValues";
    static var ARCHIVE_EXPIRATIONS:String = "PriceHistoryExpirations";
    static var HOUR:Number = 60 * 60 * 1000;
    static var DAY:Number = HOUR * 24;
    static var EXPIRE_TIMEOUT:Number = DAY * 3; // 3 days
    
    var m_tradepostInventory:Inventory;
    
    var m_PromptSaleOriginal:Function;
    var m_UpdateRightClickMenuOriginal:Function;
    var m_lastKnownPrice:Number;
    
    var m_priceHistory:Array;
    
    var m_clipLoader:MovieClipLoader;
    var m_clearTextButton:MovieClip;
    
    public static function main(swfRoot:MovieClip):Void 
    {
        var tradepostUtil = new TradepostUtil(swfRoot);
        
        swfRoot.onLoad = function() { tradepostUtil.OnLoad(); };
        swfRoot.OnUnload =  function() { tradepostUtil.OnUnload(); };
        swfRoot.OnModuleActivated = function(config:Archive) { tradepostUtil.Activate(config); };
        swfRoot.OnModuleDeactivated = function() { return tradepostUtil.Deactivate(); };
    }
    
    public function TradepostUtil(swfRoot: MovieClip) 
    {
        m_swfRoot = swfRoot;
    }
    
    public function OnLoad()
    {
        m_clipLoader = new MovieClipLoader();
        m_clipLoader.addListener(this);
        
        m_tradepostInventory = new Inventory(new com.Utils.ID32(_global.Enums.InvType.e_Type_GC_TradepostContainer, Character.GetClientCharID().GetInstance()));
        
        m_tradepostInventory.SignalItemRemoved.Connect(SignalInventoryChange, this);
        m_tradepostInventory.SignalItemAdded.Connect(SignalInventoryAdded, this);
        
        setTimeout(Delegate.create(this, WireupMethods), 50);
    }
    
    public function OnUnload()
    {
        m_tradepostInventory.SignalItemRemoved.Disconnect(SignalInventoryChange, this);
        m_tradepostInventory.SignalItemAdded.Disconnect(SignalInventoryAdded, this);
        m_tradepostInventory = undefined;
        
        //Can't really undo the method wiring we've done easily, so just close the tradepost window
        DistributedValue.SetDValue("tradepost_window", false);
        
        m_clipLoader.unloadClip(m_clearTextButton);
        
        m_clipLoader.removeListener(this);
    }
    
    function WireupMethods()
    {
        var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
        if (!buyView)
        {
            setTimeout(Delegate.create(this, WireupMethods), 50);
            return;
        }
        
        m_PromptSaleOriginal = Delegate.create(buyView, buyView.PromptSale);
        buyView.PromptSale = Delegate.create(this, PromptSaleOverride);
        
        m_UpdateRightClickMenuOriginal = Delegate.create(buyView, buyView.UpdateRightClickMenu);
        buyView.UpdateRightClickMenu = Delegate.create(this, UpdateRightClickMenuOverride);
        
        buyView.m_SellItemPromptWindow.SignalPromptResponse.Disconnect(buyView.SlotSellPromptResponse, buyView);
        buyView.m_SellItemPromptWindow.SignalPromptResponse.Connect(SlotSellPromptResponse, this);
        
        buyView.m_ItemTypeDropdownMenu.dispatchEvent({type:"select"});
        
        m_clearTextButton = buyView.createEmptyMovieClip("u_clearText", buyView.getNextHighestDepth());
        m_clipLoader.loadClip("rdb:1000624:9306661", m_clearTextButton);
        
        ShowExpiredIcons();
    }
    
    function ShowExpiredIcons()
    {
        var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
        
        var saleSlots:Array = buyView.m_SaleItemSlotsArray;
        for (var i = 0; i < saleSlots.length; i++)
        {
            var slotMc = saleSlots[i].m_SlotMC;
            slotMc.m_U_ExpiredIndicator.removeMovieClip();
            var item:InventoryItem = saleSlots[i].GetData();
            if (item)
            {
                var priceRecord = m_priceHistory[i];
                if (priceRecord.expire > 0 && priceRecord.expire - (new Date()).valueOf() < 0)
                {
                    var x:MovieClip = slotMc.createEmptyMovieClip("m_U_ExpiredIndicator", slotMc.getNextHighestDepth());
                    x.lineStyle(2, 0xFF0000);
                    x.moveTo(0, 0);
                    x.lineTo(slotMc._width, slotMc._height);
                    x.moveTo(slotMc._width, 0);
                    x.lineTo(0, slotMc._height);
                }
            }
        }
    }
    
    function SignalInventoryAdded(inventoryID:com.Utils.ID32, itemPos:Number)
    {
        if (m_lastKnownPrice > 0)
        {
            m_priceHistory[itemPos].price = m_lastKnownPrice;
            m_priceHistory[itemPos].expire = GetNewExpireTime();
            m_lastKnownPrice = 0;
        }
        ShowExpiredIcons();
    }
    
    function SignalInventoryChange()
    {
        ShowExpiredIcons();
    }
    
    function SlotSellPromptResponse(price:Number)
    {
        var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
        
        m_lastKnownPrice = price;
        
        buyView.SlotSellPromptResponse(price);
    }
    
    function UpdateRightClickMenuOverride(RightClickMode:Number, item:MCLItemInventoryItem, itemSlot:Number)
    {
        m_UpdateRightClickMenuOriginal(RightClickMode, item, itemSlot);
        
        var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
        
        if (RightClickMode == 1) //Right Click Sale
        {
            var newProvider:Array = new Array();
            var dataProvider:Array = buyView.m_RightClickMenu.dataProvider;
            
            newProvider.push(dataProvider.shift());
            
            var priceRecord = m_priceHistory[itemSlot];            
            
            if (priceRecord.price > 0)
            {
                var option:RightClickItem = new RightClickItem("Price: " + Text.AddThousandsSeparator(priceRecord.price), true, RightClickItem.CENTER_ALIGN);
                newProvider.push(option);
            }
            
            if (priceRecord.expire > 0)
            {
                var timeTillExpire:Number = priceRecord.expire - (new Date()).valueOf();
                
                var message:String;
                if (timeTillExpire < 0)
                {
                    message = "EXPIRED";
                }
                else if (timeTillExpire >= DAY)
                {
                    message = "Expires in " + Math.round(timeTillExpire/DAY) + " day(s)";
                }
                else if (timeTillExpire >= HOUR)
                {
                    message = "Expires in " + Math.round(timeTillExpire/HOUR) + " hour(s)";
                }
                else
                {
                    message = "Expires soon";
                }        
                var option:RightClickItem = new RightClickItem(message, true, RightClickItem.CENTER_ALIGN);
                newProvider.push(option);
            }
            
            while (dataProvider.length > 0)
            {
                newProvider.push(dataProvider.shift());
            }
            
            var option:RightClickItem = new RightClickItem("Price Check", false, RightClickItem.LEFT_ALIGN);
            option.SignalItemClicked.Connect(SearchOptionClickEventHandler, this);
            newProvider.push(option);
            
            buyView.m_RightClickMenu.dataProvider = newProvider;
        }
    }
    
    function SearchOptionClickEventHandler()
    {
        var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
        
        var item = m_tradepostInventory.GetItemAt(buyView.m_CancelSaleSlot);
        
        SearchForItem(item);
    }
    
    function PromptSaleOverride(inventoryID:ID32, slotID:Number)
    {
        m_PromptSaleOriginal(inventoryID, slotID);
        
        var currentInventory:Inventory = new Inventory(inventoryID);
        var item:InventoryItem = currentInventory.GetItemAt(slotID);
        
        if (!DistributedValue.GetDValue("TradepostUtil_DisableAutoSearch"))
        {
            SearchForItem(item);
            
            var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
            buyView.m_SellItemPromptWindow.m_ItemCounter.TakeFocus();
        }
    }
    
    function SearchForItem(item:InventoryItem)
    {
        var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
        
        buyView.m_SearchField.text = item.m_Name;
        var itemType = FindItemType(item);
        SetDropdownSelection(buyView.m_ItemTypeDropdownMenu, itemType, "idx");
        SetDropdownSelection(buyView.m_SubTypeDropdownMenu, LDBFormat.LDBGetText("MiscGUI", "TradePost_Class_All"), "idx");
        buyView.m_UseExactNameCheckBox.selected = true;
        SetDropdownSelection(buyView.m_RarityDropdownMenu, LDBFormat.LDBGetText("MiscGUI", "PowerLevel_" + item.m_Rarity), "idx");
        
        buyView.Search();
        
        buyView.m_UseExactNameCheckBox.selected = false;
        SetDropdownSelection(buyView.m_RarityDropdownMenu, LDBFormat.LDBGetText("MiscGUI", "TradePost_Class_All"), "idx");
    }
    
    function FindItemType(item:InventoryItem) 
    {
        for (var type in Tradepost.m_TradepostItemTypes)
        {
            for (var i in Tradepost.m_TradepostItemTypes[type])
            {
                var subtype = Tradepost.m_TradepostItemTypes[type][i];
                if (item.m_ItemTypeGUI == subtype)
                {
                    return type;
                }
            }
        }
    }
    
    function SetDropdownSelection(dropdown, targetItem, matchingProperty) 
    {
        for (var i in dropdown._dataProvider)
        {
            var item = dropdown._dataProvider[i];
            if (item[matchingProperty] == targetItem)
            {
                dropdown.selectedIndex = i;
                dropdown.dispatchEvent({type:"select"});
            }
        }
    }
    
    function GetNewExpireTime():Number
    {
        return (new Date()).valueOf() + EXPIRE_TIMEOUT;
    }
    
    public function Activate(config: Archive)
    {
        var prices:Array = config.FindEntryArray(ARCHIVE_VALUES);
        var expirations:Array = config.FindEntryArray(ARCHIVE_EXPIRATIONS);
        m_priceHistory = new Array();
        for (var i = 0; i < m_tradepostInventory.GetMaxItems(); i++ )
        {
            m_priceHistory.push(new Object());            
            m_priceHistory[i].price = prices[i] || 0;
            m_priceHistory[i].expire = expirations[i] || 0;
        }
    }
    
    public function Deactivate(): Archive
    {
        var archive: Archive = new Archive();
        for (var i = 0; i < m_priceHistory.length; i++ )
        {
            archive.AddEntry(ARCHIVE_VALUES, m_priceHistory[i].price || 0);
            archive.AddEntry(ARCHIVE_EXPIRATIONS, m_priceHistory[i].expire || 0);
        }
        return archive;
    }
    
    function onLoadComplete(target:MovieClip)
    {
        var widthHeight:Number = 22;
        if (target == m_clearTextButton)
        {
            var searchField = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView.m_SearchField;
            m_clearTextButton._x = searchField._x + searchField._width + 12;
            m_clearTextButton._y = searchField._y;
            m_clearTextButton._width = widthHeight;
            m_clearTextButton._height = widthHeight;
            
            m_clearTextButton.onPress = Delegate.create(this, ClearText);
        }
    }
    
    function ClearText()
    {
        var searchField = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView.m_SearchField;
        searchField.text = "";
    }
}