//
//  ItemDetailView.swift
//  WeItems
//

import SwiftUI

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ItemStore
    @State var item: Item
    let group: ItemGroup?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 图片
                    if let image = item.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // 名称和价格
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.name)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("¥\(String(format: "%.2f", item.price))")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                    
                    Divider()
                    
                    // 类型和分组
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: typeIcon(for: item.type))
                                .font(.caption)
                            Text(item.type)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                        
                        if let group = group {
                            HStack(spacing: 4) {
                                Image(systemName: group.icon)
                                    .font(.caption)
                                Text(group.name)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(group.color.swiftUIColor.opacity(0.1))
                            .foregroundStyle(group.color.swiftUIColor)
                            .clipShape(Capsule())
                        }
                    }
                    
                    // 详情
                    if !item.details.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("详情")
                                .font(.headline)
                            Text(item.details)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // 购买链接
                    if !item.purchaseLink.isEmpty, let url = URL(string: item.purchaseLink), 
                       url.scheme?.hasPrefix("http") == true {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("购买链接")
                                .font(.headline)
                            
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "link")
                                    Text("点击打开链接")
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    } else if !item.purchaseLink.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("购买链接")
                                .font(.headline)
                            Text(item.purchaseLink)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    
                    // 添加日期和天数统计
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text(item.listType == .wishlist ? "期盼" : "拥有")
                                .font(.headline)
                            Text("天数")
                                .font(.headline)
                        }
                        
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(daysSinceCreation)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(item.listType == .wishlist ? .pink : .blue)
                            Text("天")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("添加于 \(formattedDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // 实现心愿按钮（仅在心愿清单中显示）
                    if item.listType == .wishlist {
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                store.moveToList(itemId: item.id, listType: .items)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("实现心愿")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("物品详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func typeIcon(for type: String) -> String {
        if let itemType = ItemType(rawValue: type) {
            return itemType.icon
        }
        return "tag"
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: item.createdAt)
    }
    
    private var daysSinceCreation: Int {
        item.daysSinceCreated
    }
}

#Preview {
    ItemDetailView(
        store: ItemStore(),
        item: Item(name: "测试物品", details: "这是一个测试物品的详情描述", purchaseLink: "https://example.com", price: 999, type: "数码", listType: .wishlist),
        group: nil
    )
}
